function tests = test_WPR_Metrics_GUI
% Offline regression: UDP requests go to loopback; packets are synthetic.
tests = functiontests(localfunctions);
end

function setupOnce(testCase)
repo = fileparts(fileparts(mfilename('fullpath')));
testCase.TestData.originalPath = path;
addpath(repo);
testCase.TestData.originalVisibility = get(groot, 'DefaultFigureVisible');
set(groot, 'DefaultFigureVisible', 'off');
testCase.TestData.hadIP = ispref('XilingZU27DR', 'BoardIP');
if testCase.TestData.hadIP
    testCase.TestData.originalIP = getpref('XilingZU27DR', 'BoardIP');
end
runRoot = fullfile(repo, '过程文件', '调制选择离线验收', ...
    char(datetime('now', 'Format', 'yyyyMMdd_HHmmss_SSS')));
mkdir(runRoot);
testCase.TestData.runRoot = runRoot;
fprintf('Offline artifacts: %s\n', runRoot);
end

function teardownOnce(testCase)
set(groot, 'DefaultFigureVisible', testCase.TestData.originalVisibility);
path(testCase.TestData.originalPath);
testCase.verifyEqual(ispref('XilingZU27DR', 'BoardIP'), testCase.TestData.hadIP);
if testCase.TestData.hadIP
    testCase.verifyEqual(getpref('XilingZU27DR', 'BoardIP'), testCase.TestData.originalIP);
end
end

function setup(testCase)
fig = WPR_Metrics_GUI;
testCase.TestData.fig = fig;
state = guidata(fig);
state.output_root = tempname(testCase.TestData.runRoot);
guidata(fig, state);
end

function teardown(testCase)
fig = testCase.TestData.fig;
if isgraphics(fig)
    close(fig);
end
end

function testReferencesAndStartupDefault(testCase)
fig = testCase.TestData.fig;
state = guidata(fig);
testCase.verifyEqual(state.modulation_config.name, 'QPSK');
testCase.verifyEqual(get(state.modulation_group.SelectedObject, 'Tag'), 'QPSK');
names = {'QPSK', '8PSK', '16QAM'};
for k = 1:numel(names)
    select_mode(fig, names{k});
    state = guidata(fig);
    expected = expected_reference(names{k});
    actual = state.modulation_config.reference_constellation;
    testCase.verifySize(actual, size(expected));
    distances = abs(actual - expected.');
    testCase.verifyLessThan(max(min(distances, [], 2)), 1e-14);
    testCase.verifyEqual(mean(abs(actual).^2), 1, 'AbsTol', 1e-14);
    testCase.verifyEqual(state.modulation_config.normalization_divisor, 150 * sqrt(2));
    testCase.verifyEqual(get(get(state.constellation_axes, 'Title'), 'String'), ...
        ['Constellation (' names{k} ')']);
    plotted = get(state.reference_line, 'XData') + 1i * get(state.reference_line, 'YData');
    testCase.verifyEqual(plotted(:), actual);
end
close(fig);
fig = WPR_Metrics_GUI;
testCase.TestData.fig = fig;
state = guidata(fig);
testCase.verifyEqual(state.modulation_config.name, 'QPSK');
end

function testSyntheticMetricsAndSavedFiles(testCase)
fig = testCase.TestData.fig;
names = {'QPSK', '8PSK', '16QAM'};
factors = [1, 1.05, 1.02, exp(1i * pi / 180)];
for k = 1:numel(names)
    select_mode(fig, names{k});
    start_local(fig);
    state = guidata(fig);
    reference = repmat(expected_reference(names{k}), 8, 1);
    for n = 1:numel(factors)
        packet = make_packet(reference * factors(n), 100 + n * 10, 4 + n);
        receivedAt = state.start_time + seconds(n * 0.001);
        state.process_packet(packet, receivedAt);
        state = guidata(fig);
        recorded = state.packet_records(end);
        if n == 1
            testCase.verifyLessThan(recorded.evm_rms_percent, 1e-10);
            testCase.verifyGreaterThan(recorded.mer_db, 250);
            testCase.verifyEqual(recorded.per, 0);
        else
            errorMagnitude = abs(factors(n) - 1);
            testCase.verifyEqual(recorded.evm_rms_percent, 100 * errorMagnitude, 'AbsTol', 1e-9);
            testCase.verifyEqual(recorded.mer_db, -20 * log10(errorMagnitude), 'AbsTol', 1e-9);
            testCase.verifyEqual(recorded.per, 0.1, 'AbsTol', 1e-14);
        end
        testCase.verifyEqual(recorded.receive_time, receivedAt);
        testCase.verifyEqual(recorded.i_raw, packet.ret_iq_array(:, 1));
        testCase.verifyEqual(recorded.q_raw, packet.ret_iq_array(:, 2));
        testCase.verifyEqual(recorded.i_normalized + 1i * recorded.q_normalized, ...
            reference * factors(n), 'AbsTol', 1e-14);
        testCase.verifyEqual(recorded.modulation, names{k});
    end
    testCase.verifyEqual(get(state.metric_lines(1), 'YData'), [state.packet_records.evm_rms_percent]);
    testCase.verifyEqual(get(state.metric_lines(4), 'YData'), [state.packet_records.mer_db]);
    state.stop_capture();
    verify_idle(testCase, fig);
    verify_saved(testCase, state, names{k});
    select_mode(fig, names{mod(k, numel(names)) + 1});
    cleared = guidata(fig);
    testCase.verifyEmpty(cleared.packet_records);
    testCase.verifyTrue(isnat(cleared.start_time));
    testCase.verifyTrue(all(isnan(get(cleared.constellation_line, 'XData'))));
    for line = cleared.metric_lines.'
        testCase.verifyTrue(all(isnan(get(line, 'YData'))));
    end
    testCase.verifyEqual(get(cleared.live_text, 'String'), 'No packets received');
end
end

function testLockedUntilSavingCompletes(testCase)
fig = testCase.TestData.fig;
select_mode(fig, '16QAM');
start_local(fig);
state = guidata(fig);
verify_locked(testCase, state);
select_mode(fig, '8PSK');
state = guidata(fig);
testCase.verifyEqual(state.modulation_config.name, '16QAM');
testCase.verifyEqual(get(state.modulation_group.SelectedObject, 'Tag'), '16QAM');
originalStart = state.start_time;
invoke(state.start_button);
testCase.verifyEqual(guidata(fig).start_time, originalStart);
state.process_packet(make_packet(expected_reference('16QAM'), 100, 3), originalStart);
sawSaving = false;
listener = addlistener(state.status, 'String', 'PostSet', @during_save);
cleanup = onCleanup(@() delete(listener));
state.stop_capture();
testCase.verifyTrue(sawSaving);
verify_idle(testCase, fig);
verify_saved(testCase, guidata(fig), '16QAM');

    function during_save(~, ~)
        current = guidata(fig);
        if ~strcmp(get(current.status, 'String'), 'Saving capture ...')
            return;
        end
        sawSaving = true;
        testCase.verifyTrue(current.saving);
        testCase.verifyFalse(current.running);
        verify_locked(testCase, current);
        select_mode(fig, 'QPSK');
        invoke(current.start_button);
        current = guidata(fig);
        testCase.verifyEqual(current.modulation_config.name, '16QAM');
        testCase.verifyEqual(get(current.modulation_group.SelectedObject, 'Tag'), '16QAM');
        testCase.verifyFalse(current.running);
    end
end

function testRepeatedCaptureResetsPerAndMetrics(testCase)
fig = testCase.TestData.fig;
select_mode(fig, '8PSK');
for cycle = 1:2
    start_local(fig);
    state = guidata(fig);
    testCase.verifyEmpty(state.packet_records);
    testCase.verifyTrue(all(isnan(get(state.metric_lines(1), 'YData'))));
    reference = repmat(expected_reference('8PSK'), cycle, 1);
    state.process_packet(make_packet(reference * (1 + 0.02 * cycle), 1000 * cycle, 100), state.start_time);
    state = guidata(fig);
    testCase.verifyEqual(state.packet_records(1).packet_number, 1);
    testCase.verifyEqual(state.packet_records(1).per, 0);
    testCase.verifyEqual(state.packet_records(1).evm_rms_percent, 2 * cycle, 'AbsTol', 1e-10);
    state.process_packet(make_packet(reference, 1000 * cycle + 10, 100 + cycle), ...
        state.start_time + milliseconds(1));
    state = guidata(fig);
    testCase.verifyEqual(state.packet_records(2).per, cycle / 10, 'AbsTol', 1e-14);
    state.stop_capture();
end
end

function testZeroDataStopForEveryMode(testCase)
fig = testCase.TestData.fig;
for name = {'QPSK', '8PSK', '16QAM'}
    select_mode(fig, name{1});
    start_local(fig);
    state = guidata(fig);
    state.stop_capture();
    verify_idle(testCase, fig);
    verify_saved(testCase, state, name{1});
end
end

function testStartupFailureRestoresControls(testCase)
fig = testCase.TestData.fig;
state = guidata(fig);
mockFolder = fullfile(testCase.TestData.runRoot, 'temporary_udp_failure');
mkdir(fullfile(mockFolder, '@udp'));
fid = fopen(fullfile(mockFolder, '@udp', 'udp.m'), 'w');
fprintf(fid, 'function varargout = udp(varargin)\nerror(''WPR:OfflineStartupFailure'', ''Controlled offline startup failure'');\nend\n');
fclose(fid);
addpath(mockFolder, '-begin');
rehash;
clear udp;
cleanup = onCleanup(@() remove_udp_mock(mockFolder));
testCase.assertEqual(which('udp'), fullfile(mockFolder, '@udp', 'udp.m'));
state.active_ip = '127.0.0.1';
set(state.ip_edit, 'String', state.active_ip);
guidata(fig, state);
invoke(state.start_button);
verify_idle(testCase, fig);
state = guidata(fig);
testCase.verifySubstring(get(state.status, 'String'), 'UDP start failed:');
testCase.verifySubstring(get(state.status, 'String'), 'Controlled offline startup failure');
clear cleanup;
select_mode(fig, '16QAM');
start_local(fig);
state = guidata(fig);
state.stop_capture();
verify_idle(testCase, fig);
end

function testSaveFailureRestoresControls(testCase)
fig = testCase.TestData.fig;
select_mode(fig, '16QAM');
start_local(fig);
state = guidata(fig);
state.process_packet(make_packet(expected_reference('16QAM'), 100, 0), state.start_time);
state = guidata(fig);
blockedRoot = fullfile(testCase.TestData.runRoot, 'output_root_is_a_file');
fid = fopen(blockedRoot, 'w');
fclose(fid);
state.output_root = blockedRoot;
guidata(fig, state);
state.stop_capture();
verify_idle(testCase, fig);
state = guidata(fig);
testCase.verifySubstring(get(state.status, 'String'), 'Save failed:');
testCase.verifyNumElements(state.packet_records, 1);
select_mode(fig, '8PSK');
testCase.verifyEqual(guidata(fig).modulation_config.name, '8PSK');
end

function testCloseDuringCaptureSavesAndCleansUp(testCase)
fig = testCase.TestData.fig;
start_local(fig);
state = guidata(fig);
client = state.client;
requestTimer = state.request_timer;
close(fig);
testCase.verifyFalse(isgraphics(fig));
testCase.verifyFalse(isvalid(client));
testCase.verifyFalse(isvalid(requestTimer));
verify_saved(testCase, state, 'QPSK');
end

function select_mode(fig, name)
state = guidata(fig);
button = findobj(state.modulation_buttons, 'Tag', name);
set(state.modulation_group, 'SelectedObject', button);
callback = get(state.modulation_group, 'SelectionChangedFcn');
callback(state.modulation_group, struct('NewValue', button));
end

function start_local(fig)
state = guidata(fig);
state.active_ip = '127.0.0.1';
set(state.ip_edit, 'String', state.active_ip);
guidata(fig, state);
invoke(state.start_button);
state = guidata(fig);
assert(state.running, 'Offline start failed: %s', get(state.status, 'String'));
stop(state.request_timer); % Keep acquisition deterministic; STOP deletes it.
end

function invoke(control)
callback = get(control, 'Callback');
callback(control, []);
end

function remove_udp_mock(mockFolder)
rmpath(mockFolder);
clear udp;
rehash;
end

function reference = expected_reference(name)
switch name
    case 'QPSK'
        reference = [1+1i; 1-1i; -1+1i; -1-1i] / sqrt(2);
    case '8PSK'
        reference = exp(1i * (pi / 8 + (0:7)' * pi / 4));
    case '16QAM'
        [i, q] = ndgrid([-3 -1 1 3]);
        reference = (i(:) + 1i * q(:)) / sqrt(10);
end
end

function packet = make_packet(symbols, rx, crcErrors)
raw = symbols * (150 * sqrt(2));
packet = struct('type', 63, 'pac_tx_cnt', rx + 1, 'pac_rx_cnt', rx, ...
    'pac_rx_crc_ok_cnt', rx - crcErrors, 'pac_rx_crc_err_cnt', crcErrors, ...
    'rms', -31.25, 'ret_iq_array', [real(raw(:)), imag(raw(:))]);
end

function verify_locked(testCase, state)
controls = [state.modulation_buttons(:); state.ip_edit; state.apply_ip_button; state.start_button];
for control = controls.'
    testCase.verifyEqual(get(control, 'Enable'), 'off');
end
end

function verify_idle(testCase, fig)
state = guidata(fig);
testCase.verifyFalse(state.running);
testCase.verifyFalse(state.saving);
testCase.verifyEmpty(state.client);
testCase.verifyEmpty(state.request_timer);
controls = [state.modulation_buttons(:); state.ip_edit; state.apply_ip_button; state.start_button];
for control = controls.'
    testCase.verifyEqual(get(control, 'Enable'), 'on');
end
testCase.verifyEqual(get(state.stop_button, 'Enable'), 'off');
end

function verify_saved(testCase, state, name)
folders = dir(fullfile(state.output_root, 'constellation_*'));
testCase.assertNotEmpty(folders);
folder = '';
for k = 1:numel(folders)
    candidate = fullfile(folders(k).folder, folders(k).name);
    data = load(fullfile(candidate, 'metrics_recording.mat'));
    if data.metadata.start_time == state.start_time
        folder = candidate;
        break;
    end
end
testCase.assertNotEmpty(folder, 'Capture with the expected start time was not saved.');
testCase.verifyEqual(data.metadata.modulation, name);
testCase.verifyEqual(data.metadata.modulation_order, numel(expected_reference(name)));
testCase.verifyEqual(data.metadata.reference_constellation, state.modulation_config.reference_constellation);
testCase.verifyEqual(data.metadata.normalization_divisor, 150 * sqrt(2));
if strcmp(name, '8PSK')
    testCase.verifyEqual(data.metadata.reference_phase_offset_rad, pi / 8);
end
testCase.verifyFalse(data.metadata.board_modulation_controlled);
testCase.verifyEqual(data.metadata.packet_count, numel(state.packet_records));
testCase.verifyEqual(data.packetRecords, state.packet_records);
testCase.verifyEqual(data.packetMetrics.modulation, repmat(string(name), height(data.packetMetrics), 1));
testCase.verifyEqual(data.constellationPoints.modulation, repmat(string(name), height(data.constellationPoints), 1));
testCase.verifyTrue(isfile(fullfile(folder, 'dashboard.png')));
metrics = readtable(fullfile(folder, 'packet_metrics.csv'), 'TextType', 'string');
points = readtable(fullfile(folder, 'constellation_points.csv'), 'TextType', 'string');
testCase.verifyEqual(height(metrics), height(data.packetMetrics));
testCase.verifyEqual(height(points), height(data.constellationPoints));
testCase.verifyTrue(ismember('modulation', metrics.Properties.VariableNames));
testCase.verifyTrue(ismember('modulation', points.Properties.VariableNames));
if ~isempty(points)
    testCase.verifyEqual(string(metrics.modulation), repmat(string(name), height(metrics), 1));
    testCase.verifyEqual(string(points.modulation), repmat(string(name), height(points), 1));
    testCase.verifyEqual(points.i_raw, data.constellationPoints.i_raw, 'AbsTol', 1e-10);
    testCase.verifyEqual(points.q_raw, data.constellationPoints.q_raw, 'AbsTol', 1e-10);
    testCase.verifyEqual(points.i_normalized, data.constellationPoints.i_normalized, 'AbsTol', 1e-12);
    testCase.verifyEqual(points.q_normalized, data.constellationPoints.q_normalized, 'AbsTol', 1e-12);
    for k = 1:numel(state.packet_records)
        selected = points.packet_number == k;
        csvTime = datetime(points.receive_time(selected), 'InputFormat', 'yyyy-MM-dd HH:mm:ss.SSS');
        delta = abs(seconds(csvTime - state.packet_records(k).receive_time));
        testCase.verifyLessThanOrEqual(max(delta), 0.001);
    end
end
end
