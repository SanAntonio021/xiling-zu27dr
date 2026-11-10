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
runRoot = fullfile(repo, '过程文件', 'MAT保存离线验收', ...
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
testCase.verifyEqual(get(state.save_button, 'Enable'), 'off');
testCase.verifyEqual(get(state.file_name_edit, 'String'), '');
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
    previousFiles = capture_inventory(guidata(fig).output_root);
    start_local(fig);
    state = guidata(fig);
    reference = repmat(expected_reference(names{k}), 8, 1);
    state.process_packet(make_packet(reference, 100, 4), state.start_time);
    for n = 1:numel(factors)
        packet = make_packet(reference * factors(n), 100 + n * 10, 4 + n);
        receivedAt = state.start_time + seconds(n * 0.001);
        state.process_packet(packet, receivedAt);
        state = guidata(fig);
        recorded = state.packet_records(end);
        if n == 1
            testCase.verifyLessThan(recorded.evm_rms_percent, 1e-10);
            testCase.verifyGreaterThan(recorded.mer_db, 250);
        else
            errorMagnitude = abs(factors(n) - 1);
            testCase.verifyEqual(recorded.evm_rms_percent, 100 * errorMagnitude, 'AbsTol', 1e-9);
            testCase.verifyEqual(recorded.mer_db, -20 * log10(errorMagnitude), 'AbsTol', 1e-9);
        end
        testCase.verifyEqual(recorded.per, 0.1, 'AbsTol', 1e-14);
        testCase.verifyEqual(recorded.rx_packet_increment, 10);
        testCase.verifyEqual(recorded.receive_time, receivedAt);
        testCase.verifyEqual(recorded.i_raw, packet.ret_iq_array(:, 1));
        testCase.verifyEqual(recorded.q_raw, packet.ret_iq_array(:, 2));
        testCase.verifyEqual(recorded.i_normalized + 1i * recorded.q_normalized, ...
            reference * factors(n), 'AbsTol', 1e-14);
        testCase.verifyEqual(recorded.modulation, names{k});
    end
    testCase.verifyEqual(get(state.metric_lines(1), 'YData'), [state.packet_records.evm_rms_percent]);
    testCase.verifyEqual(get(state.metric_lines(2), 'YData'), [state.packet_records.per_upper_95]);
    testCase.verifyEqual(get(state.metric_lines(3), 'YData'), [state.packet_records.ber_upper_95]);
    testCase.verifyEqual(get(state.metric_lines(4), 'YData'), [state.packet_records.mer_db]);
    state.stop_capture();
    verify_idle(testCase, fig);
    state = guidata(fig);
    verify_unsaved(testCase, state, previousFiles);
    capture = state.pending_capture;
    verify_snapshot_selection(testCase, fig, capture);
    invoke(state.save_button);
    state = guidata(fig);
    verify_saved(testCase, state.last_output_folder, capture);
    testCase.verifyEmpty(state.pending_capture);
    testCase.verifyEqual(get(state.save_button, 'Enable'), 'off');
    invoke(state.save_button);
    testCase.verifyNumElements(dir(fullfile(state.output_root, 'constellation_*')), k);
    select_mode(fig, names{mod(k, numel(names)) + 1});
    cleared = guidata(fig);
    testCase.verifyEmpty(cleared.packet_records);
    testCase.verifyTrue(isnat(cleared.start_time));
    testCase.verifyTrue(all(isnan(get(cleared.constellation_line, 'XData'))));
    for line = cleared.metric_lines.'
        testCase.verifyTrue(all(isnan(get(line, 'YData'))));
    end
    testCase.verifyEqual(get(cleared.metric_values(1), 'String'), '--');
    testCase.verifyEqual(get(cleared.summary_values(1), 'String'), ...
        {'数据更新：0 次'; '本次新增：--'});
    testCase.verifyEqual(get(cleared.summary_values(4), 'String'), '板卡累计');
end
end

function testLockedUntilSavingCompletes(testCase)
fig = testCase.TestData.fig;
select_mode(fig, '16QAM');
start_local(fig);
state = guidata(fig);
verify_locked(testCase, state);
invoke(state.save_button);
testCase.verifyFalse(isfolder(state.output_root));
select_mode(fig, '8PSK');
state = guidata(fig);
testCase.verifyEqual(state.modulation_config.name, '16QAM');
testCase.verifyEqual(get(state.modulation_group.SelectedObject, 'Tag'), '16QAM');
originalStart = state.start_time;
invoke(state.start_button);
testCase.verifyEqual(guidata(fig).start_time, originalStart);
state.process_packet(make_packet(expected_reference('16QAM'), 99, 3), originalStart);
state.process_packet(make_packet(expected_reference('16QAM'), 100, 3), originalStart);
state.stop_capture();
state = guidata(fig);
capture = state.pending_capture;
sawSaving = false;
listener = addlistener(state.status, 'String', 'PostSet', @during_save);
cleanup = onCleanup(@() delete(listener));
invoke(state.save_button);
testCase.verifyTrue(sawSaving);
verify_idle(testCase, fig);
verify_saved(testCase, guidata(fig).last_output_folder, capture);

    function during_save(~, ~)
        current = guidata(fig);
        if ~strcmp(get(current.status, 'String'), 'Saving capture ...')
            return;
        end
        sawSaving = true;
        testCase.verifyTrue(current.saving);
        testCase.verifyFalse(current.running);
        testCase.verifyEqual(get(current.save_button, 'Enable'), 'off');
        verify_locked(testCase, current);
        select_mode(fig, 'QPSK');
        invoke(current.start_button);
        invoke(current.save_button);
        close(fig);
        testCase.verifyTrue(isgraphics(fig));
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
    testCase.verifyEmpty(state.counter_baseline);
    testCase.verifyEmpty(state.pending_capture);
    testCase.verifyEqual(get(state.save_button, 'Enable'), 'off');
    testCase.verifyTrue(all(isnan(get(state.metric_lines(1), 'YData'))));
    reference = repmat(expected_reference('8PSK'), cycle, 1);
    state.process_packet(make_packet(reference * (1 + 0.02 * cycle), 1000 * cycle, 100), state.start_time);
    state = guidata(fig);
    testCase.verifyEmpty(state.packet_records);
    testCase.verifyEqual(state.counter_baseline.pac_rx_cnt, 1000 * cycle);
    testCase.verifyEqual(state.counter_baseline.pac_rx_crc_err_cnt, 100);
    testCase.verifyEqual(get(state.summary_values(1), 'String'), ...
        {'数据更新：0 次'; '本次新增：--'});
    state.process_packet(make_packet(reference * (1 + 0.02 * cycle), ...
        1000 * cycle + 10, 100 + cycle), state.start_time + milliseconds(1));
    state = guidata(fig);
    testCase.verifyEqual(state.packet_records(1).packet_number, 1);
    testCase.verifyEqual(state.packet_records(1).per, cycle / 10, 'AbsTol', 1e-14);
    testCase.verifyTrue(isfinite(state.packet_records(1).per_upper_95));
    testCase.verifyTrue(isfinite(state.packet_records(1).ber_upper_95));
    testCase.verifyEqual(state.packet_records(1).per_sample_count, 10);
    testCase.verifyEqual(state.packet_records(1).per_error_count, cycle);
    testCase.verifyEqual(state.packet_records(1).rx_packet_increment, 10);
    testCase.verifyEqual(get(state.summary_values(1), 'String'), ...
        {'数据更新：1 次'; '本次新增：10 包'});
    testCase.verifyEqual(state.packet_records(1).evm_rms_percent, 2 * cycle, 'AbsTol', 1e-10);
    state.process_packet(make_packet(reference, 1000 * cycle + 20, 100 + 2 * cycle), ...
        state.start_time + milliseconds(2));
    state = guidata(fig);
    testCase.verifyEqual(state.packet_records(2).per, cycle / 10, 'AbsTol', 1e-14);
    testCase.verifyEqual(state.packet_records(2).per_sample_count, 20);
    testCase.verifyEqual(state.packet_records(2).per_error_count, 2 * cycle);
    testCase.verifyEqual(get(state.summary_values(1), 'String'), ...
        {'数据更新：2 次'; '本次新增：10 包'});
    state.stop_capture();
    verify_unsaved(testCase, guidata(fig));
end
end

function testZeroErrorsUpperBoundAndNoNewPackets(testCase)
fig = testCase.TestData.fig;
start_local(fig);
state = guidata(fig);
reference = expected_reference('QPSK');
state.process_packet(make_packet(reference, 100, 7), state.start_time);
state = guidata(fig);
testCase.verifyEmpty(state.packet_records);
testCase.verifyEqual(get(state.metric_values(2), 'String'), '--');
testCase.verifyEqual(get(state.metric_values(3), 'String'), '--');
testCase.verifyEqual(get(state.per_details, 'String'), '本轮错包/收包 0/0');

sampleCounts = [1 10 1000 100000 1000000000];
upperBounds = zeros(size(sampleCounts));
for index = 1:numel(sampleCounts)
    n = sampleCounts(index);
    state.process_packet(make_packet(reference, 100 + n, 7), state.start_time + milliseconds(index));
    state = guidata(fig);
    record = state.packet_records(end);
    upperBounds(index) = record.per_upper_95;
    testCase.verifyEqual(record.per, 0);
    testCase.verifyEqual(record.ber_estimate, 0);
    testCase.verifyEqual(record.ber_upper_95, -expm1(log1p(-record.per_upper_95) / 108000));
    testCase.verifyEqual(record.per_sample_count, n);
    testCase.verifyEqual(record.per_error_count, 0);
    testCase.verifyEqual((1 - record.per_upper_95)^n, 0.05, 'AbsTol', 1e-7);
    testCase.verifyEqual(get(state.metric_values(2), 'String'), sprintf('%.4e', record.per_upper_95));
    testCase.verifyEqual(get(state.metric_values(3), 'String'), sprintf('%.4e', record.ber_upper_95));
    testCase.verifyEqual(get(state.metric_axes(2), 'XLim'), [0 index / 1000], 'AbsTol', 1e-10);
end
testCase.verifyLessThan(diff(upperBounds), zeros(1, numel(upperBounds) - 1));
testCase.verifyEqual(upperBounds(1), 0.95, 'AbsTol', 1e-14);
testCase.verifyEqual(upperBounds(4), 2.995687401942795e-5, 'AbsTol', 1e-15);
testCase.verifyEqual(get(state.metric_lines(2), 'YData'), [state.packet_records.per_upper_95]);
testCase.verifyEqual(get(state.per_details, 'String'), '本轮错包/收包 0/1000000000');
previous = state.packet_records(end);
state.process_packet(make_packet(reference, 100 + sampleCounts(end), 7), ...
    state.start_time + milliseconds(100));
state = guidata(fig);
testCase.verifyEqual(state.packet_records(end).per_upper_95, previous.per_upper_95);
testCase.verifyEqual(state.packet_records(end).per_sample_count, previous.per_sample_count);
testCase.verifyNotEqual(state.packet_records(end).elapsed_seconds, previous.elapsed_seconds);
testCase.verifyEqual(get(state.summary_values(1), 'String'), ...
    {'数据更新：6 次'; '本次新增：0 包'});
% No STOP snapshot is needed here; normal teardown exercises close without saving.
end

function testNonzeroErrorsExactBoundAndBerUsesObservedPer(testCase)
fig = testCase.TestData.fig;
start_local(fig);
state = guidata(fig);
reference = expected_reference('QPSK');
state.process_packet(make_packet(reference, 0, 0), state.start_time);
samples = [10 20 20 30 30];
errors = [0 1 5 5 30];
upperBounds = zeros(size(samples));
for index = 1:numel(samples)
    n = samples(index);
    k = errors(index);
    state.process_packet(make_packet(reference, n, k), state.start_time + milliseconds(index));
    state = guidata(fig);
    record = state.packet_records(end);
    upperBounds(index) = record.per_upper_95;
    testCase.verifyEqual(record.per, k / n);
    testCase.verifyGreaterThanOrEqual(record.per_upper_95, record.per);
    testCase.verifyLessThanOrEqual(record.per_upper_95, 1);
    testCase.verifyEqual(record.ber_upper_95, -expm1(log1p(-record.per_upper_95) / 108000));
    if k < n
        % Independently invert the binomial CDF using direct finite summation.
        j = 0:k;
        p = record.per_upper_95;
        cdf = sum(exp(gammaln(n + 1) - gammaln(j + 1) - gammaln(n - j + 1) + ...
            j * log(p) + (n - j) * log1p(-p)));
        testCase.verifyEqual(cdf, 0.05, 'AbsTol', 1e-12);
        expectedBER = 1 - (1 - k / n)^(1 / 108000);
        testCase.verifyEqual(record.ber_estimate, expectedBER, 'AbsTol', 1e-15);
    else
        testCase.verifyEqual(record.per_upper_95, 1);
        testCase.verifyEqual(record.ber_estimate, 1);
    end
end
testCase.verifyGreaterThan(upperBounds(3), upperBounds(2)); % New errors can raise the bound.
testCase.verifyLessThan(upperBounds(4), upperBounds(3)); % More error-free packets lower it.
state.stop_capture();
state = guidata(fig);
capture = state.pending_capture;
invoke(state.save_button);
verify_saved(testCase, guidata(fig).last_output_folder, capture);
end

function testInconsistentErrorCountShowsUnavailable(testCase)
fig = testCase.TestData.fig;
start_local(fig);
state = guidata(fig);
reference = expected_reference('QPSK');
state.process_packet(make_packet(reference, 100, 0), state.start_time);
state.process_packet(make_packet(reference, 101, 2), state.start_time + milliseconds(1));
state = guidata(fig);
record = state.packet_records(end);
testCase.verifyEqual(record.per_sample_count, 1);
testCase.verifyEqual(record.per_error_count, 2);
testCase.verifyTrue(isnan(record.per));
testCase.verifyTrue(isnan(record.per_upper_95));
testCase.verifyTrue(isnan(record.ber_estimate));
testCase.verifyTrue(isnan(record.ber_upper_95));
testCase.verifyEqual(get(state.metric_values(2), 'String'), '--');
testCase.verifyEqual(get(state.metric_values(3), 'String'), '--');
testCase.verifyEqual(get(state.per_details, 'String'), '计数异常  本轮错包/收包 2/1');
end

function testFullSessionUpperBoundTrends(testCase)
fig = testCase.TestData.fig;
start_local(fig);
state = guidata(fig);
reference = expected_reference('QPSK');
state.process_packet(make_packet(reference, 0, 0), state.start_time);
for n = 1:60
    state.process_packet(make_packet(reference, n * 10, 0), state.start_time + seconds(n));
end
state = guidata(fig);
for index = [2 3]
    testCase.verifyNumElements(get(state.metric_lines(index), 'XData'), 60);
    testCase.verifyEqual(get(state.metric_axes(index), 'XLim'), [0 60]);
end
for index = [1 4 5]
    testCase.verifyNumElements(get(state.metric_lines(index), 'XData'), 50);
    testCase.verifyEqual(get(state.metric_axes(index), 'XLim'), [11 60]);
end
testCase.verifyEqual(get(state.metric_lines(3), 'YData'), [state.packet_records.ber_upper_95]);
state.stop_capture();
start_local(fig);
state = guidata(fig);
testCase.verifyEmpty(state.packet_records);
testCase.verifyTrue(all(isnan(get(state.metric_lines(2), 'YData'))));
testCase.verifyTrue(all(isnan(get(state.metric_lines(3), 'YData'))));
end

function testZeroDataStopForEveryMode(testCase)
fig = testCase.TestData.fig;
for name = {'QPSK', '8PSK', '16QAM'}
    select_mode(fig, name{1});
    start_local(fig);
    state = guidata(fig);
    state.stop_capture();
    verify_idle(testCase, fig);
    state = guidata(fig);
    testCase.verifyEmpty(state.pending_capture);
    testCase.verifyEqual(get(state.save_button, 'Enable'), 'off');
    invoke(state.save_button);
    testCase.verifyFalse(isfolder(state.output_root));
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
testCase.verifyEqual(get(state.save_button, 'Enable'), 'off');
testCase.verifyFalse(isfolder(state.output_root));
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
state.process_packet(make_packet(expected_reference('16QAM'), 99, 0), state.start_time);
state.process_packet(make_packet(expected_reference('16QAM'), 100, 0), state.start_time);
state = guidata(fig);
blockedRoot = fullfile(testCase.TestData.runRoot, 'output_root_is_a_file');
fid = fopen(blockedRoot, 'w');
fclose(fid);
state.output_root = blockedRoot;
guidata(fig, state);
state.stop_capture();
state = guidata(fig);
capture = state.pending_capture;
invoke(state.save_button);
verify_idle(testCase, fig);
state = guidata(fig);
testCase.verifySubstring(get(state.status, 'String'), 'Save failed:');
testCase.verifyNumElements(state.packet_records, 1);
testCase.verifyEqual(state.pending_capture, capture);
testCase.verifyEqual(get(state.save_button, 'Enable'), 'on');
select_mode(fig, '8PSK');
testCase.verifyEqual(guidata(fig).modulation_config.name, '8PSK');
state = guidata(fig);
state.output_root = tempname(testCase.TestData.runRoot);
guidata(fig, state);
invoke(state.save_button);
verify_saved(testCase, guidata(fig).last_output_folder, capture);
end

function testCloseDuringCaptureDoesNotSaveAndCleansUp(testCase)
fig = testCase.TestData.fig;
start_local(fig);
state = guidata(fig);
state.process_packet(make_packet(expected_reference('QPSK'), 99, 0), state.start_time);
state.process_packet(make_packet(expected_reference('QPSK'), 100, 0), state.start_time);
client = state.client;
requestTimer = state.request_timer;
close(fig);
testCase.verifyFalse(isgraphics(fig));
testCase.verifyFalse(isvalid(client));
testCase.verifyFalse(isvalid(requestTimer));
testCase.verifyFalse(isfolder(state.output_root));
end

function testCloseWithPendingDataDoesNotSave(testCase)
fig = testCase.TestData.fig;
start_local(fig);
state = guidata(fig);
state.process_packet(make_packet(expected_reference('QPSK'), 99, 0), state.start_time);
state.process_packet(make_packet(expected_reference('QPSK'), 100, 0), state.start_time);
state.stop_capture();
state = guidata(fig);
verify_unsaved(testCase, state);
close(fig);
testCase.verifyFalse(isgraphics(fig));
testCase.verifyFalse(isfolder(state.output_root));
end

function testDelayedSaveKeepsStoppedConfigAndImage(testCase)
fig = testCase.TestData.fig;
select_mode(fig, '16QAM');
start_local(fig);
state = guidata(fig);
state.process_packet(make_packet(expected_reference('16QAM'), 99, 2), state.start_time);
state.process_packet(make_packet(expected_reference('16QAM') * 1.05, 100, 2), state.start_time);
state.stop_capture();
state = guidata(fig);
capture = state.pending_capture;
testCase.assertNotEmpty(capture.dashboard_image);
pause(0.05);
select_mode(fig, '8PSK');
state = guidata(fig);
testCase.verifyEmpty(state.packet_records);
testCase.verifyEqual(state.pending_capture, capture);
testCase.verifyEqual(get(state.save_button, 'Enable'), 'on');
hadIP = ispref('XilingZU27DR', 'BoardIP');
savedIP = [];
if hadIP
    savedIP = getpref('XilingZU27DR', 'BoardIP');
end
cleanup = onCleanup(@() restore_ip_preference(hadIP, savedIP));
set(state.ip_edit, 'String', '192.168.0.28');
invoke(state.apply_ip_button);
state = guidata(fig);
testCase.verifyEqual(state.active_ip, '192.168.0.28');
testCase.verifyEqual(state.pending_capture, capture);
invoke(state.save_button);
state = guidata(fig);
verify_saved(testCase, state.last_output_folder, capture);
saved = load(fullfile(state.last_output_folder, 'metrics_recording.mat'), 'metadata');
testCase.verifyEqual(saved.metadata.source_ip, '127.0.0.1');
savedEndTime = datetime(saved.metadata.end_time, ...
    'InputFormat', 'yyyy-MM-dd HH:mm:ss.SSS');
testCase.verifyLessThan(savedEndTime, datetime('now') - seconds(0.04));
end

function testImageWriteFailureRetainsCaptureForRetry(testCase)
fig = testCase.TestData.fig;
start_local(fig);
state = guidata(fig);
state.process_packet(make_packet(expected_reference('QPSK'), 99, 0), state.start_time);
state.process_packet(make_packet(expected_reference('QPSK'), 100, 0), state.start_time);
state.stop_capture();
state = guidata(fig);
capture = state.pending_capture;
mockFolder = fullfile(testCase.TestData.runRoot, 'temporary_imwrite_failure');
mkdir(mockFolder);
fid = fopen(fullfile(mockFolder, 'imwrite.m'), 'w');
fprintf(fid, 'function imwrite(varargin)\nerror(''WPR:OfflineImageFailure'', ''Controlled offline image write failure'');\nend\n');
fclose(fid);
addpath(mockFolder, '-begin');
rehash;
clear imwrite;
cleanup = onCleanup(@() remove_imwrite_mock(mockFolder));
testCase.assertEqual(which('imwrite'), fullfile(mockFolder, 'imwrite.m'));
invoke(state.save_button);
verify_idle(testCase, fig);
state = guidata(fig);
testCase.verifySubstring(get(state.status, 'String'), 'Controlled offline image write failure');
testCase.verifyEqual(state.pending_capture, capture);
testCase.verifyEqual(get(state.save_button, 'Enable'), 'on');
testCase.verifyEmpty(state.last_output_folder);
clear cleanup;
invoke(state.save_button);
state = guidata(fig);
verify_saved(testCase, state.last_output_folder, capture);
testCase.verifyEmpty(state.pending_capture);
end

function testFileNameUsesStoppedCaptureAndStaysForNextRun(testCase)
fig = testCase.TestData.fig;
select_mode(fig, '16QAM');
start_local(fig);
state = guidata(fig);
state.start_time = state.start_time - seconds(90);
guidata(fig, state);
state.process_packet(make_packet(expected_reference('16QAM'), 99, 0), state.start_time);
state.process_packet(make_packet(expected_reference('16QAM'), 100, 0), state.start_time);
state.stop_capture();
state = guidata(fig);
capture = state.pending_capture;
select_mode(fig, '8PSK');
state = guidata(fig);
set(state.file_name_edit, 'String', '  103GHz_正向_衰减10dB  ');
invoke(state.save_button);
state = guidata(fig);
verify_saved(testCase, state.last_output_folder, capture);
saved = load(fullfile(state.last_output_folder, 'metrics_recording.mat'), 'metadata');
stamp = capture.start_time;
stamp.Format = 'yyyyMMdd_HHmmss';
expectedFolder = ['103GHz_正向_衰减10dB_16QAM_' char(stamp)];
testCase.verifyEqual(state.last_output_folder, fullfile(state.output_root, expectedFolder));
testCase.verifyEqual(saved.metadata.file_name_prefix, '103GHz_正向_衰减10dB');
testCase.verifyEqual(saved.metadata.record_folder_name, expectedFolder);
testCase.verifyEqual(get(state.file_name_edit, 'String'), '103GHz_正向_衰减10dB');
start_local(fig);
state = guidata(fig);
testCase.verifyEqual(get(state.file_name_edit, 'String'), '103GHz_正向_衰减10dB');
state.stop_capture();
end

function testFileNameHintAndPendingSaveHighlight(testCase)
fig = testCase.TestData.fig;
state = guidata(fig);
testCase.verifyEqual(get(state.file_name_hint, 'String'), '输入要保存的文件名称，留空自动命名');
testCase.verifyEqual(char(get(state.file_name_hint, 'Visible')), 'on');
testCase.verifyEqual(get(state.file_name_edit, 'String'), '');
testCase.verifyEqual(get(state.file_name_edit, 'BackgroundColor'), [1 1 1]);
start_local(fig);
state = guidata(fig);
testCase.verifyEqual(get(state.file_name_edit, 'BackgroundColor'), [1 1 1]);
state.process_packet(make_packet(expected_reference('QPSK'), 99, 0), state.start_time);
state.process_packet(make_packet(expected_reference('QPSK'), 100, 0), state.start_time);
state.stop_capture();
state = guidata(fig);
capture = state.pending_capture;
verify_unsaved(testCase, state);
testCase.verifyEqual(char(get(state.file_name_hint, 'Visible')), 'on');
imwrite(capture.dashboard_image, fullfile(testCase.TestData.runRoot, 'file_name_pending_hint.png'));
set(state.file_name_edit, 'String', '命名检查');
callback = get(state.file_name_edit, 'KeyReleaseFcn');
callback(state.file_name_edit, []);
testCase.verifyEqual(char(get(state.file_name_hint, 'Visible')), 'off');
set(state.file_name_edit, 'String', '');
invoke(state.file_name_edit);
testCase.verifyEqual(char(get(state.file_name_hint, 'Visible')), 'on');
invoke(state.save_button);
state = guidata(fig);
verify_saved(testCase, state.last_output_folder, capture);
saved = load(fullfile(state.last_output_folder, 'metrics_recording.mat'), 'metadata');
testCase.verifyEmpty(saved.metadata.file_name_prefix);
testCase.verifyEqual(char(get(state.file_name_hint, 'Visible')), 'on');
testCase.verifyEqual(get(state.file_name_edit, 'BackgroundColor'), [1 1 1]);
testCase.verifyEqual(get(state.file_name_label, 'ForegroundColor'), [0.85 0.9 0.85]);
end

function testBlankFileNameAndExistingPathsAreNotOverwritten(testCase)
fig = testCase.TestData.fig;
start_local(fig);
state = guidata(fig);
state.process_packet(make_packet(expected_reference('QPSK'), 99, 0), state.start_time);
state.process_packet(make_packet(expected_reference('QPSK'), 100, 0), state.start_time);
state.stop_capture();
state = guidata(fig);
capture = state.pending_capture;
stamp = capture.start_time;
stamp.Format = 'yyyyMMdd_HHmmss';
baseName = ['constellation_' char(stamp)];
existingFolder = fullfile(state.output_root, baseName);
mkdir(existingFolder);
existingFile = fullfile(state.output_root, [baseName '_1']);
fid = fopen(existingFile, 'w');
fprintf(fid, 'keep this existing file');
fclose(fid);
set(state.file_name_edit, 'String', '   ');
invoke(state.save_button);
state = guidata(fig);
verify_saved(testCase, state.last_output_folder, capture);
testCase.verifyEqual(state.last_output_folder, fullfile(state.output_root, [baseName '_2']));
testCase.verifyTrue(isfolder(existingFolder));
testCase.verifyEqual(fileread(existingFile), 'keep this existing file');
saved = load(fullfile(state.last_output_folder, 'metrics_recording.mat'), 'metadata');
testCase.verifyEmpty(saved.metadata.file_name_prefix);
testCase.verifyEqual(saved.metadata.record_folder_name, [baseName '_2']);
end

function testOfflinePreviewWithoutBoard(testCase)
originalFigure = testCase.TestData.fig;
originalState = guidata(originalFigure);
testCase.verifyError(@() WPR_Metrics_Preview, 'WPR:PreviewWindowExists');
testCase.verifyEqual(guidata(originalFigure), originalState);
close(originalFigure);
fig = WPR_Metrics_Preview;
testCase.TestData.fig = fig;
state = guidata(fig);
testCase.verifyFalse(state.running);
testCase.verifyEmpty(state.client);
testCase.verifyEmpty(state.request_timer);
testCase.verifyEqual(state.active_ip, 'OFFLINE_PREVIEW');
testCase.verifySubstring(get(fig, 'Name'), '模拟数据');
testCase.verifySubstring(get(state.constellation_axes.Title, 'String'), '模拟数据');
testCase.verifyEqual(numel(state.pending_capture.packet_records), 50);
testCase.verifyEqual(get(state.file_name_edit, 'BackgroundColor'), [1 0.96 0.80]);
testCase.verifyEqual(get(state.save_button, 'Enable'), 'on');
state.output_root = tempname(testCase.TestData.runRoot);
guidata(fig, state);
set(state.file_name_edit, 'String', '离线预览测试');
capture = state.pending_capture;
invoke(state.save_button);
state = guidata(fig);
verify_saved(testCase, state.last_output_folder, capture);
saved = load(fullfile(state.last_output_folder, 'metrics_recording.mat'), 'metadata');
testCase.verifyEqual(saved.metadata.source_ip, 'OFFLINE_PREVIEW');
testCase.verifyEqual(saved.metadata.file_name_prefix, '离线预览测试');
invoke(state.start_button);
invoke(state.apply_ip_button);
state = guidata(fig);
testCase.verifyFalse(state.running);
testCase.verifyEmpty(state.client);
testCase.verifyEmpty(state.request_timer);
end

function testInvalidFileNameKeepsCaptureForCorrection(testCase)
fig = testCase.TestData.fig;
start_local(fig);
state = guidata(fig);
state.process_packet(make_packet(expected_reference('QPSK'), 99, 0), state.start_time);
state.process_packet(make_packet(expected_reference('QPSK'), 100, 0), state.start_time);
state.stop_capture();
state = guidata(fig);
capture = state.pending_capture;
for invalidCharacter = ['<>:"/\|?*' char(1)]
    set(state.file_name_edit, 'String', ['test' invalidCharacter 'name']);
    invoke(state.save_button);
    state = guidata(fig);
    testCase.verifySubstring(get(state.status, 'String'), '文件名称不能包含');
    testCase.verifyEqual(state.pending_capture, capture);
    testCase.verifyEqual(get(state.save_button, 'Enable'), 'on');
    testCase.verifyFalse(isfolder(state.output_root));
    verify_idle(testCase, fig);
end
set(state.file_name_edit, 'String', '修正后');
invoke(state.save_button);
state = guidata(fig);
verify_saved(testCase, state.last_output_folder, capture);
end

function testNativePointArraysKeepVariableReportLengths(testCase)
fig = testCase.TestData.fig;
start_local(fig);
state = guidata(fig);
reference = expected_reference('QPSK') * 1.05;
state.process_packet(make_packet(reference, 100, 0), state.start_time);
% Include a report larger than the former Excel JSON cell limit.
pointCounts = [4 17 9000 1 33];
for n = 1:numel(pointCounts)
    symbols = repmat(reference, ceil(pointCounts(n) / numel(reference)), 1);
    state.process_packet(make_packet(symbols(1:pointCounts(n)), 100 + n * 10, n), ...
        state.start_time + milliseconds(n));
end
state.stop_capture();
state = guidata(fig);
capture = state.pending_capture;
invoke(state.save_button);
state = guidata(fig);
verify_saved(testCase, state.last_output_folder, capture);
end

function testMatPreservesUnavailableAndInfiniteMetrics(testCase)
fig = testCase.TestData.fig;
start_local(fig);
state = guidata(fig);
state.process_packet(make_packet(expected_reference('QPSK'), 100, 0), state.start_time);
for n = 1:3
    state.process_packet(make_packet(expected_reference('QPSK') * 1.05, 100 + n * 10, 0), ...
        state.start_time + milliseconds(n));
end
state = guidata(fig);
% MAT must preserve IEEE values directly, without text or blank-cell conversion.
state.packet_records(1).mer_db = Inf;
state.packet_records(2).mer_db = -Inf;
state.packet_records(3).mer_db = NaN;
guidata(fig, state);
state.stop_capture();
state = guidata(fig);
capture = state.pending_capture;
invoke(state.save_button);
state = guidata(fig);
verify_saved(testCase, state.last_output_folder, capture);
end

function testMetricLabelsSummaryAndLayout(testCase)
fig = testCase.TestData.fig;
start_local(fig);
state = guidata(fig);
state.process_packet(make_packet(expected_reference('QPSK') * 1.05, 4294967294, 2), state.start_time);
state.process_packet(make_packet(expected_reference('QPSK') * 1.05, 4294967294, 2), ...
    state.start_time + milliseconds(1));
state = guidata(fig);
testCase.verifyEqual(get(state.metric_values(1), 'String'), '5.000 %');
testCase.verifyEqual(get(state.metric_values(2), 'String'), '--');
testCase.verifyTrue(contains(get(state.metric_values(2), 'TooltipString'), 'one-sided'));
for n = [100 1000 10000 100000]
    state.process_packet(make_packet(expected_reference('QPSK') * 1.05, 4294967294 + n, 2), ...
        state.start_time + milliseconds(log10(n)));
    state = guidata(fig);
end
testCase.verifyEqual(get(state.metric_values(2), 'String'), '2.9957e-05');
testCase.verifyEqual(get(state.per_details, 'String'), '本轮错包/收包 0/100000');
testCase.verifyEqual(get(state.summary_values(4), 'String'), '板卡累计');
testCase.verifyEqual(get(state.summary_values(1), 'String'), ...
    {'数据更新：5 次'; '本次新增：90000 包'});
testCase.verifyEqual(get(state.metric_values(5), 'String'), '-31.250 dB');
for ax = state.metric_axes.'
    testCase.verifyEqual(char(get(ax, 'XGrid')), 'on');
    testCase.verifyEqual(char(get(ax, 'YGrid')), 'on');
    testCase.verifyEqual(char(get(ax, 'Box')), 'on');
    testCase.verifyEqual(double(ax.YAxis.Exponent), 0);
end
controls = findall(fig, 'Type', 'uicontrol', 'Style', 'text');
for control = controls.'
    testCase.verifyFalse(any(contains(string(get(control, 'String')), '|')));
end
originalPosition = get(fig, 'Position');
actualDetail = get(state.per_details, 'String');
actualUpdate = get(state.summary_values(1), 'String');
longestDetail = '计数异常  本轮错包/收包 4294967294/4294967294';
for dimensions = [1480 900; 1200 760].'
    set(fig, 'Position', [originalPosition(1:2) dimensions.']);
    set(state.per_details, 'String', longestDetail);
    set(state.summary_values(1), 'String', ...
        {'数据更新：4294967294 次'; '本次新增：4294967294 包'});
    drawnow;
    metricLabels = [findall(fig, 'Type', 'uicontrol', 'Style', 'text', 'String', 'PER · 95% 上限'); ...
        findall(fig, 'Type', 'uicontrol', 'Style', 'text', 'String', '推算 BER · 95% 上限')];
    for control = [state.summary_values; state.metric_values; state.per_details; ...
            metricLabels; state.file_name_label; state.file_name_hint].'
        position = get(control, 'Position');
        extent = get(control, 'Extent');
        testCase.verifyLessThanOrEqual(extent(3), position(3) + 0.002);
        testCase.verifyLessThanOrEqual(extent(4), position(4) + 0.002);
    end
    statusPosition = get(state.status, 'Position');
    namePosition = get(state.file_name_label, 'Position');
    editPosition = get(state.file_name_edit, 'Position');
    testCase.verifyLessThan(statusPosition(1) + statusPosition(3), namePosition(1));
    testCase.verifyLessThan(namePosition(1) + namePosition(3), editPosition(1));
    metricNames = {'EVM RMS', 'PER · 95% 上限', '推算 BER · 95% 上限', 'MER', 'Rx IF Power'};
    for metricIndex = 1:numel(metricNames)
        label = findall(fig, 'Type', 'uicontrol', 'Style', 'text', 'String', metricNames{metricIndex});
        axisPosition = get(state.metric_axes(metricIndex), 'Position');
        labelPosition = get(label, 'Position');
        gap = labelPosition(2) - (axisPosition(2) + axisPosition(4));
        if metricIndex == 2
            testCase.verifyLessThanOrEqual(gap, 0.031);
            detailPosition = get(state.per_details, 'Position');
            testCase.verifyLessThanOrEqual(detailPosition(2) - (axisPosition(2) + axisPosition(4)), 0.003);
            testCase.verifyLessThanOrEqual(labelPosition(2) - (detailPosition(2) + detailPosition(4)), 0.004);
        else
            testCase.verifyLessThanOrEqual(gap, 0.005);
        end
    end
    set(state.per_details, 'String', actualDetail);
    set(state.summary_values(1), 'String', actualUpdate);
    if dimensions(1) == 1200
        print(fig, '-RGBImage', '-r150');
        preview = print(fig, '-RGBImage', '-r150');
        imwrite(preview, fullfile(testCase.TestData.runRoot, 'offline_layout_preview_1200x760.png'));
    end
end
set(fig, 'Position', originalPosition);
state.stop_capture();
state = guidata(fig);
imwrite(state.pending_capture.dashboard_image, fullfile(testCase.TestData.runRoot, 'offline_layout_preview.png'));
end

function testBaselineBeforeFirstUpdateAndSavedIncrements(testCase)
fig = testCase.TestData.fig;
start_local(fig);
state = guidata(fig);
reference = expected_reference('QPSK');
baselineAt = state.start_time + milliseconds(3);
state.process_packet(make_packet(reference * 1.5, 100000, 17), baselineAt);
state = guidata(fig);
testCase.verifyEmpty(state.packet_records);
testCase.verifyEqual(state.counter_baseline.receive_time, baselineAt);
testCase.verifyEqual(state.counter_baseline.pac_rx_cnt, 100000);
testCase.verifyEqual(state.counter_baseline.pac_rx_crc_err_cnt, 17);
testCase.verifyEqual(get(state.summary_values(1), 'String'), ...
    {'数据更新：0 次'; '本次新增：--'});
testCase.verifyTrue(all(isnan(get(state.constellation_line, 'XData'))));
testCase.verifyEqual(get(state.metric_values(1), 'String'), '--');
testCase.verifyEqual(get(state.save_button, 'Enable'), 'off');

firstAt = baselineAt + milliseconds(50);
state.process_packet(make_packet(reference * 1.05, 101912, 17), firstAt);
state = guidata(fig);
testCase.assertNumElements(state.packet_records, 1);
record = state.packet_records(1);
testCase.verifyEqual(record.packet_number, 1);
testCase.verifyEqual(record.receive_time, firstAt);
testCase.verifyEqual(record.rx_packet_increment, 1912);
testCase.verifyEqual(record.per_sample_count, 1912);
testCase.verifyEqual(record.per_error_count, 0);
testCase.verifyEqual(record.evm_rms_percent, 5, 'AbsTol', 1e-10);
testCase.verifyEqual(record.per_upper_95, -expm1(log(0.05) / 1912));
testCase.verifyEqual(get(state.summary_values(1), 'String'), ...
    {'数据更新：1 次'; '本次新增：1912 包'});
state.process_packet(make_packet(reference, 103823, 18), firstAt + milliseconds(50));
state = guidata(fig);
testCase.verifyEqual([state.packet_records.rx_packet_increment], [1912 1911]);
testCase.verifyEqual(state.packet_records(2).per_sample_count, 3823);
testCase.verifyEqual(state.packet_records(2).per_error_count, 1);
state.stop_capture();
state = guidata(fig);
capture = state.pending_capture;
invoke(state.save_button);
state = guidata(fig);
verify_saved(testCase, state.last_output_folder, capture);
saved = load(fullfile(state.last_output_folder, 'metrics_recording.mat'));
testCase.verifyEqual(saved.packetMetrics.rx_packet_increment, [1912; 1911]);
testCase.verifyEqual(saved.metadata.counter_baseline.pac_rx_cnt, 100000);
testCase.verifyEqual(string(saved.metadata.counter_baseline.receive_time), format_test_time(baselineAt));
testCase.verifyEqual(saved.metadata.packet_count, 2);
testCase.verifyEqual(saved.metadata.point_count, 2 * numel(reference));
testCase.verifyEqual(get(state.status, 'String'), ...
    sprintf('已保存 2 次更新 / %d 个点', 2 * numel(reference)));
end

function testBaselineOnlyStopForEveryMode(testCase)
fig = testCase.TestData.fig;
for name = {'QPSK', '8PSK', '16QAM'}
    select_mode(fig, name{1});
    start_local(fig);
    state = guidata(fig);
    testCase.verifyEmpty(state.counter_baseline);
    state.process_packet(make_packet(expected_reference(name{1}), 5000, 3), state.start_time);
    state = guidata(fig);
    testCase.verifyEmpty(state.packet_records);
    testCase.verifyEqual(state.counter_baseline.pac_rx_cnt, 5000);
    state.stop_capture();
    verify_idle(testCase, fig);
    state = guidata(fig);
    testCase.verifyEmpty(state.pending_capture);
    testCase.verifyEqual(get(state.save_button, 'Enable'), 'off');
    invoke(state.save_button);
    testCase.verifyFalse(isfolder(state.output_root));
end
end

function testInvalidBaselineAndUnavailableIncrement(testCase)
fig = testCase.TestData.fig;
start_local(fig);
state = guidata(fig);
reference = expected_reference('QPSK');
state.process_packet(make_packet(reference, NaN, 0), state.start_time);
state = guidata(fig);
testCase.verifyEmpty(state.counter_baseline);
testCase.verifyEmpty(state.packet_records);
testCase.verifySubstring(get(state.status, 'String'), '计数起点无效');
state.process_packet(make_packet(reference, 100, 0), state.start_time + milliseconds(1));
state.process_packet(make_packet(reference, 110, 0), state.start_time + milliseconds(2));
state.process_packet(make_packet(reference, 110, 0), state.start_time + milliseconds(3));
state = guidata(fig);
testCase.verifyEqual([state.packet_records.rx_packet_increment], [10 0]);
testCase.verifyEqual(get(state.summary_values(1), 'String'), ...
    {'数据更新：2 次'; '本次新增：0 包'});
state.process_packet(make_packet(reference, 109, 0), state.start_time + milliseconds(4));
state = guidata(fig);
testCase.verifyTrue(isnan(state.packet_records(end).rx_packet_increment));
testCase.verifyEqual(get(state.summary_values(1), 'String'), ...
    {'数据更新：3 次'; '本次新增：--'});
state.stop_capture();
state = guidata(fig);
capture = state.pending_capture;
invoke(state.save_button);
verify_saved(testCase, guidata(fig).last_output_folder, capture);
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

function remove_imwrite_mock(mockFolder)
rmpath(mockFolder);
clear imwrite;
rehash;
end

function restore_ip_preference(hadIP, savedIP)
if hadIP
    setpref('XilingZU27DR', 'BoardIP', savedIP);
elseif ispref('XilingZU27DR', 'BoardIP')
    rmpref('XilingZU27DR', 'BoardIP');
end
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
controls = [state.modulation_buttons(:); state.ip_edit; state.apply_ip_button; ...
    state.start_button; state.file_name_edit];
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
controls = [state.modulation_buttons(:); state.ip_edit; state.apply_ip_button; ...
    state.start_button; state.file_name_edit];
for control = controls.'
    testCase.verifyEqual(get(control, 'Enable'), 'on');
end
testCase.verifyEqual(get(state.stop_button, 'Enable'), 'off');
if isempty(state.pending_capture)
    testCase.verifyEqual(get(state.file_name_edit, 'BackgroundColor'), [1 1 1]);
    testCase.verifyEqual(get(state.file_name_label, 'ForegroundColor'), [0.85 0.9 0.85]);
else
    testCase.verifyEqual(get(state.file_name_edit, 'BackgroundColor'), [1 0.96 0.80]);
    testCase.verifyEqual(get(state.file_name_label, 'ForegroundColor'), [1 0.63 0.14]);
end
end

function verify_unsaved(testCase, state, previousFiles)
if nargin < 3
    testCase.verifyFalse(isfolder(state.output_root));
else
    currentFiles = capture_inventory(state.output_root);
    testCase.verifyEqual(currentFiles, previousFiles);
end
testCase.assertNotEmpty(state.pending_capture);
testCase.verifyEqual(get(state.save_button, 'Enable'), 'on');
testCase.verifyEqual(get(state.save_button, 'BackgroundColor'), [1 0.63 0.14]);
testCase.verifyEqual(get(state.file_name_edit, 'BackgroundColor'), [1 0.96 0.80]);
testCase.verifyEqual(get(state.file_name_hint, 'BackgroundColor'), [1 0.96 0.80]);
testCase.verifyEqual(get(state.file_name_label, 'ForegroundColor'), [1 0.63 0.14]);
testCase.verifySubstring(get(state.status, 'String'), '未保存');
end

function verify_saved(testCase, folder, capture)
currentState = guidata(testCase.TestData.fig);
testCase.assertTrue(isfolder(folder), get(currentState.status, 'String'));
name = capture.modulation_config.name;
matPath = fullfile(folder, 'metrics_recording.mat');
testCase.assertTrue(isfile(matPath));
saved = load(matPath);
testCase.verifyEqual(sort(fieldnames(saved)), ...
    sort({'constellationPoints'; 'packetMetrics'; 'metadata'}));
points = saved.constellationPoints;
metrics = saved.packetMetrics;
metadata = saved.metadata;
testCase.verifyClass(points, 'struct');
testCase.verifyClass(metrics, 'struct');
testCase.verifyClass(metadata, 'struct');
testCase.verifyEqual(sort(fieldnames(points)), ...
    sort({'packet_start_index'; 'point_count'; 'i_raw'; 'q_raw'}));
testCase.verifyEqual(metadata.format_version, 1);
testCase.verifyClass(metadata.file_name_prefix, 'char');
[~, folderName] = fileparts(folder);
testCase.verifyEqual(metadata.record_folder_name, folderName);
testCase.verifyEqual(string(metadata.start_time), format_test_time(capture.start_time));
testCase.verifyEqual(string(metadata.end_time), format_test_time(capture.end_time));
testCase.verifyEqual(metadata.duration_seconds, max(0, seconds(capture.end_time - capture.start_time)));
testCase.verifyEqual(metadata.packet_count, numel(capture.packet_records));
testCase.verifyEqual(metadata.point_count, total_capture_points(capture.packet_records));
testCase.verifyEqual(metadata.source_ip, capture.active_ip);
testCase.verifyEqual(metadata.source_port, 5001);
testCase.verifyEqual(metadata.modulation, name);
testCase.verifyEqual(metadata.modulation_order, capture.modulation_config.order);
testCase.verifyEqual(metadata.reference_constellation, capture.modulation_config.reference_constellation);
testCase.verifyEqual(metadata.reference_phase_offset_rad, capture.modulation_config.phase_offset_rad);
testCase.verifyEqual(metadata.normalization_divisor, 150 * sqrt(2));
testCase.verifyEqual(metadata.per_confidence_level, 0.95);
testCase.verifyEqual(metadata.per_upper_method, 'One-sided Clopper-Pearson');
testCase.verifyFalse(metadata.per_counter_basis_verified);
testCase.verifySubstring(metadata.per_confidence_scope, 'Pointwise');
testCase.verifyEqual(metadata.counter_baseline.pac_tx_cnt, capture.counter_baseline.pac_tx_cnt);
testCase.verifyEqual(metadata.counter_baseline.pac_rx_cnt, capture.counter_baseline.pac_rx_cnt);
testCase.verifyEqual(metadata.counter_baseline.pac_rx_crc_ok_cnt, capture.counter_baseline.pac_rx_crc_ok_cnt);
testCase.verifyEqual(metadata.counter_baseline.pac_rx_crc_err_cnt, capture.counter_baseline.pac_rx_crc_err_cnt);
testCase.verifyEqual(string(metadata.counter_baseline.receive_time), ...
    format_test_time(capture.counter_baseline.receive_time));
testCase.verifySubstring(metadata.rx_packet_increment_definition, 'update 1 uses counter_baseline');
testCase.verifySubstring(metadata.ber_type, 'Observed-PER');
testCase.verifySubstring(metadata.ber_upper_95_definition, 'per_upper_95');
testCase.verifyEqual(metadata.ber_packet_length_bits, 108000);
testCase.verifySubstring(metadata.receive_time_definition, 'Computer UDP callback');
testCase.verifySubstring(metadata.rx_if_power_definition, 'not calibrated RSSI');
testCase.verifySubstring(metadata.point_storage_definition, '1-based');
testCase.verifyFalse(metadata.board_modulation_controlled);
testCase.verifyTrue(isfile(fullfile(folder, 'dashboard.png')));
testCase.verifyEqual(imread(fullfile(folder, 'dashboard.png')), capture.dashboard_image);
files = capture_inventory(folder);
testCase.verifyNumElements(files(~[files.isdir]), 2);
records = capture.packet_records;
expectedTimes = format_test_times([records.receive_time]');
testCase.verifyEqual(metrics.packet_number, [records.packet_number]');
testCase.verifyClass(metrics.receive_time, 'char');
testCase.verifyEqual(string(metrics.receive_time), expectedTimes);
metricFields = {'elapsed_seconds', 'pac_tx_cnt', 'pac_rx_cnt', 'rx_packet_increment', ...
    'pac_rx_crc_ok_cnt', 'pac_rx_crc_err_cnt', 'evm_rms_percent', 'mer_db', ...
    'per', 'per_upper_95', 'per_sample_count', 'per_error_count', 'ber_estimate', 'ber_upper_95'};
testCase.verifyEqual(sort(fieldnames(metrics)), ...
    sort([metricFields(:); {'packet_number'; 'receive_time'; 'rx_if_power'}]));
for field = metricFields
    testCase.verifyEqual(metrics.(field{1}), [records.(field{1})]');
end
testCase.verifyEqual(metrics.rx_if_power, [records.rms]');
testCase.verifyEqual(points.point_count, arrayfun(@(record) numel(record.i_raw), records)');
testCase.verifyEqual(points.packet_start_index, [1; 1 + cumsum(points.point_count(1:end-1))]);
testCase.verifyEqual(points.i_raw, vertcat(records.i_raw));
testCase.verifyEqual(points.q_raw, vertcat(records.q_raw));
for k = 1:numel(records)
    rows = points.packet_start_index(k) + (0:points.point_count(k)-1);
    testCase.verifyEqual(points.i_raw(rows), records(k).i_raw);
    testCase.verifyEqual(points.q_raw(rows), records(k).q_raw);
    testCase.verifyEqual(points.i_raw(rows) / metadata.normalization_divisor, records(k).i_normalized);
    testCase.verifyEqual(points.q_raw(rows) / metadata.normalization_divisor, records(k).q_normalized);
end
end

function formatted = format_test_time(timeValue)
formatted = format_test_times(timeValue);
formatted = formatted(1);
end

function formatted = format_test_times(times)
times = times(:);
times.Format = 'yyyy-MM-dd HH:mm:ss.SSS';
formatted = string(times);
end

function count = total_capture_points(records)
count = sum(arrayfun(@(record) numel(record.i_raw), records));
end

function verify_snapshot_selection(testCase, fig, capture)
% Catch native-radio export lag even when SelectedObject and Value are correct.
state = guidata(fig);
image = capture.dashboard_image;
figurePosition = getpixelposition(fig);
scale = [size(image, 2) / figurePosition(3), size(image, 1) / figurePosition(4)];
for button = state.modulation_buttons.'
    position = getpixelposition(button, true);
    % Inspect only the radio glyph, excluding ClearType-coloured caption edges.
    x = max(1, floor(position(1) * scale(1))):min(size(image, 2), ceil((position(1) + 18) * scale(1)));
    y = max(1, floor(size(image, 1) - (position(2) + position(4)) * scale(2))): ...
        min(size(image, 1), ceil(size(image, 1) - position(2) * scale(2)));
    region = double(image(y, x, :));
    blue = region(:, :, 3) > 150 & region(:, :, 1) < 100 & region(:, :, 3) > 1.2 * region(:, :, 2);
    selected = strcmp(get(button, 'Tag'), capture.modulation_config.name);
    % Selected glyphs cover ~100 logical pixels; antialiasing on empty
    % glyphs contributes only 1-4 output pixels on the Windows renderer.
    testCase.verifyEqual(nnz(blue) / prod(scale) > 10, selected, ...
        sprintf('Saved radio marker disagrees with capture mode %s (%s button).', ...
        capture.modulation_config.name, get(button, 'Tag')));
end
end

function files = capture_inventory(root)
files = dir(fullfile(root, '**', '*'));
files = files(~ismember({files.name}, {'.', '..'}) & ...
    ~endsWith({files.name}, '.baiduyun.uploading.cfg'));
% Sync software can change directory timestamps while uploading old captures.
% Keep file sizes/times but compare directory identity only.
for index = find([files.isdir])
    files(index).date = '';
    files(index).datenum = 0;
    files(index).bytes = 0;
end
end
