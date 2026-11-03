function fig = WPR_Metrics_GUI()
% Real-time constellation and link-metric monitor for the ZU27DR board.

existing = findall(0, 'Type', 'figure', 'Tag', 'WPR_Metrics_GUI');
if ~isempty(existing)
    fig = existing(1);
    figure(fig);
    return;
end

deviceIP = get_saved_device_ip();
screen = get(0, 'ScreenSize');
width = min(1480, screen(3) - 80);
height = min(900, screen(4) - 100);
left = max(20, (screen(3) - width) / 2);
bottom = max(30, (screen(4) - height) / 2);
fig = figure('Name', 'ZU27DR Metrics Monitor', 'NumberTitle', 'off', ...
    'MenuBar', 'none', 'Color', [0.02 0.02 0.02], ...
    'Position', [left bottom width height], 'Tag', 'WPR_Metrics_GUI', ...
    'CloseRequestFcn', @close_gui);

emptyRecords = struct('packet_number', {}, 'receive_time', {}, ...
    'elapsed_seconds', {}, 'pac_tx_cnt', {}, 'pac_rx_cnt', {}, ...
    'pac_rx_crc_ok_cnt', {}, 'pac_rx_crc_err_cnt', {}, 'rms', {}, ...
    'evm_rms_percent', {}, 'mer_db', {}, 'per', {}, 'ber_estimate', {}, ...
    'i_raw', {}, 'q_raw', {}, 'i_normalized', {}, 'q_normalized', {});
state = struct('active_ip', deviceIP, 'running', false, 'client', [], ...
    'request_timer', [], 'start_time', NaT, 'packet_records', emptyRecords, ...
    'last_rx_count', NaN, 'last_crc_err_count', NaN, ...
    'session_rx_delta', 0, 'session_crc_err_delta', 0, ...
    'output_root', fullfile(fileparts(mfilename('fullpath')), 'constellation_records'), ...
    'metric_lines', gobjects(5, 1), 'metric_axes', gobjects(5, 1));
evmCalculator = comm.EVM('MaximumEVMOutputPort', true);
evmCalculator.ReferenceSignalSource = 'Estimated from reference constellation';
evmCalculator.ReferenceConstellation = qammod(0:3, 4, 'gray', 'UnitAveragePower', true);
merCalculator = comm.MER('MinimumMEROutputPort', true);
merCalculator.ReferenceSignalSource = 'Estimated from reference constellation';
merCalculator.ReferenceConstellation = qammod(0:3, 4, 'gray', 'UnitAveragePower', true);
state.process_packet = @(packet, receivedAt) process_packet(fig, packet, receivedAt);
state.stop_capture = @() stop_capture(fig);
state.decode_frame = @decode_metrics_frame;
guidata(fig, state);

uicontrol(fig, 'Style', 'text', 'String', 'Board IP', ...
    'Units', 'normalized', 'Position', [0.025 0.932 0.055 0.045], ...
    'ForegroundColor', [0.85 0.9 0.85], 'BackgroundColor', [0.02 0.02 0.02], ...
    'HorizontalAlignment', 'left', 'FontSize', 10);
state = guidata(fig);
state.ip_edit = uicontrol(fig, 'Style', 'edit', 'String', deviceIP, ...
    'Units', 'normalized', 'Position', [0.082 0.932 0.15 0.047], ...
    'BackgroundColor', 'white', 'ForegroundColor', 'black', 'FontSize', 10, ...
    'Tag', 'WPR_Metrics_IP');
state.apply_ip_button = uicontrol(fig, 'Style', 'pushbutton', 'String', 'Apply IP', ...
    'Units', 'normalized', 'Position', [0.24 0.932 0.085 0.047], ...
    'FontSize', 10, 'Callback', @apply_ip);
state.start_button = uicontrol(fig, 'Style', 'pushbutton', 'String', 'START', ...
    'Units', 'normalized', 'Position', [0.34 0.932 0.09 0.047], ...
    'FontSize', 10, 'FontWeight', 'bold', 'Callback', @start_capture);
state.stop_button = uicontrol(fig, 'Style', 'pushbutton', 'String', 'STOP', ...
    'Units', 'normalized', 'Position', [0.445 0.932 0.09 0.047], ...
    'FontSize', 10, 'FontWeight', 'bold', 'Enable', 'off', ...
    'Callback', @stop_capture);
state.status = uicontrol(fig, 'Style', 'text', 'String', 'Ready', ...
    'Units', 'normalized', 'Position', [0.56 0.932 0.41 0.047], ...
    'ForegroundColor', [0.35 0.95 0.45], 'BackgroundColor', [0.02 0.02 0.02], ...
    'HorizontalAlignment', 'left', 'FontSize', 10, 'Tag', 'WPR_Metrics_Status');
guidata(fig, state);

state = guidata(fig);
state.live_text = uicontrol(fig, 'Style', 'text', 'String', 'No packets received', ...
    'Units', 'normalized', 'Position', [0.035 0.86 0.93 0.052], ...
    'ForegroundColor', [0.35 0.95 0.45], 'BackgroundColor', [0.02 0.02 0.02], ...
    'HorizontalAlignment', 'left', 'FontName', 'Consolas', 'FontSize', 10);
guidata(fig, state);

constellationAxes = axes('Parent', fig, 'Units', 'normalized', ...
    'Position', [0.045 0.18 0.56 0.65], 'Color', 'k', ...
    'XColor', [0.25 0.9 0.35], 'YColor', [0.25 0.9 0.35], ...
    'FontSize', 10, 'Box', 'on');
hold(constellationAxes, 'on');
state.constellation_line = plot(constellationAxes, NaN, NaN, '.', ...
    'Color', [1 0.7 0], 'MarkerSize', 9, 'Tag', 'WPR_Metrics_Constellation');
state.constellation_axes = constellationAxes;
guidata(fig, state);
reference = qammod(0:3, 4, 'gray', 'UnitAveragePower', true);
plot(constellationAxes, real(reference), imag(reference), 'r+', ...
    'LineWidth', 1.5, 'MarkerSize', 10);
axis(constellationAxes, [-2 2 -2 2]);
axis(constellationAxes, 'square');
grid(constellationAxes, 'on');
set(constellationAxes, 'GridColor', [0.15 0.5 0.2]);
xlabel(constellationAxes, 'In-phase');
ylabel(constellationAxes, 'Quadrature');
title(constellationAxes, 'Constellation (QAM-4)', 'Color', [0.25 0.9 0.35]);

metricNames = {'EVM RMS (%)', 'PER', 'BER estimate', 'MER (dB)', 'Rx IF Power (dB)'};
metricColors = [1 0.7 0; 1 0.3 0.25; 0.25 0.8 1; 0.25 0.9 0.45; 1 0.55 0.2];
metricY = [0.735 0.592 0.449 0.306 0.163];
for metricIndex = 1:numel(metricNames)
    ax = axes('Parent', fig, 'Units', 'normalized', ...
        'Position', [0.665 metricY(metricIndex) 0.29 0.12], 'Color', 'k', ...
        'XColor', [0.75 0.85 0.75], 'YColor', [0.75 0.85 0.75], ...
        'FontSize', 8, 'Box', 'on');
    lineHandle = plot(ax, NaN, NaN, 'LineWidth', 1.5, 'Color', metricColors(metricIndex, :));
    grid(ax, 'on');
    set(ax, 'GridColor', [0.15 0.35 0.18]);
    title(ax, metricNames{metricIndex}, 'Color', metricColors(metricIndex, :), 'FontSize', 9);
    xlabel(ax, 'Time (s)', 'FontSize', 8);
    state = guidata(fig);
    state.metric_axes(metricIndex) = ax;
    state.metric_lines(metricIndex) = lineHandle;
    guidata(fig, state);
end

uicontrol(fig, 'Style', 'text', ...
    'String', 'Rx IF Power is the board-reported rms field; BER is estimated from PER.', ...
    'Units', 'normalized', 'Position', [0.045 0.09 0.91 0.035], ...
    'ForegroundColor', [0.7 0.7 0.7], 'BackgroundColor', [0.02 0.02 0.02], ...
    'HorizontalAlignment', 'left', 'FontSize', 9);

function apply_ip(~, ~)
    state = guidata(fig);
    requestedIP = strtrim(get(state.ip_edit, 'String'));
    if ~is_valid_ipv4_address(requestedIP)
        set(state.status, 'String', 'Invalid IPv4 address', ...
            'ForegroundColor', [1 0.3 0.25]);
        return;
    end
    if state.running
        set(state.status, 'String', 'Stop capture before changing IP', ...
            'ForegroundColor', [1 0.7 0]);
        return;
    end
    state.active_ip = requestedIP;
    setpref('XilingZU27DR', 'BoardIP', requestedIP);
    set(state.status, 'String', ['IP applied: ' requestedIP], ...
        'ForegroundColor', [0.35 0.95 0.45]);
    guidata(fig, state);
end

function start_capture(~, ~)
    state = guidata(fig);
    requestedIP = strtrim(get(state.ip_edit, 'String'));
    if ~is_valid_ipv4_address(requestedIP)
        set(state.status, 'String', 'Enter a valid IPv4 address', ...
            'ForegroundColor', [1 0.3 0.25]);
        return;
    end
    if ~strcmp(requestedIP, state.active_ip)
        set(state.status, 'String', 'Click Apply IP before starting', ...
            'ForegroundColor', [1 0.7 0]);
        return;
    end

    state.packet_records = state.packet_records([]);
    state.start_time = datetime('now', 'Format', 'yyyy-MM-dd HH:mm:ss.SSS');
    state.last_rx_count = NaN;
    state.last_crc_err_count = NaN;
    state.session_rx_delta = 0;
    state.session_crc_err_delta = 0;
    set(state.constellation_line, 'XData', NaN, 'YData', NaN);
    for lineIndex = 1:numel(state.metric_lines)
        set(state.metric_lines(lineIndex), 'XData', NaN, 'YData', NaN);
    end
    set(state.live_text, 'String', 'Waiting for packets ...');
    state.running = true;
    set(state.start_button, 'Enable', 'off');
    set(state.stop_button, 'Enable', 'on');
    set(state.apply_ip_button, 'Enable', 'off');
    set(state.ip_edit, 'Enable', 'off');
    set(state.status, 'String', ['Opening UDP to ' state.active_ip ':5001 ...'], ...
        'ForegroundColor', [1 0.7 0]);
    guidata(fig, state);

    client = [];
    timerHandle = [];
    try
        client = udp(state.active_ip, 5001);
        client.InputBufferSize = 1024 * 100;
        client.OutputBufferSize = 8192;
        client.EnablePortSharing = 'on';
        client.Tag = 'WPR_Metrics_GUI';
        client.DatagramReceivedFcn = @(obj, event) receive_datagram(fig, obj, event);
        fopen(client);
        timerHandle = timer('ExecutionMode', 'fixedSpacing', 'Period', 0.05, ...
            'BusyMode', 'drop', 'TimerFcn', @(~, ~) send_monitor_request(fig));
        state = guidata(fig);
        state.client = client;
        state.request_timer = timerHandle;
        set(state.status, 'String', ['Capturing from ' state.active_ip], ...
            'ForegroundColor', [0.35 0.95 0.45]);
        guidata(fig, state);
        start(timerHandle);
        send_monitor_request(fig);
    catch ME
        state = guidata(fig);
        state.running = false;
        close_client(client);
        stop_timer(timerHandle);
        state.client = [];
        state.request_timer = [];
        set(state.start_button, 'Enable', 'on');
        set(state.stop_button, 'Enable', 'off');
        set(state.apply_ip_button, 'Enable', 'on');
        set(state.ip_edit, 'Enable', 'on');
        set(state.status, 'String', ['UDP start failed: ' ME.message], ...
            'ForegroundColor', [1 0.3 0.25]);
        guidata(fig, state);
    end
end

function send_monitor_request(~)
    if ~ishandle(fig)
        return;
    end
    state = guidata(fig);
    if ~state.running || isempty(state.client) || ~isvalid(state.client)
        return;
    end
    request = jsonencode(struct('comment', 'comment', 'type', 1, ...
        'dst', 'mon', 'remote_time', char(datetime('now', 'Format', 'yyyy-MM-dd HH:mm:ss')), ...
        'terminal_id', 55055, 'op_cmd', 0));
    data = [int2asc2(length(request) + 4), int2asc2(1), request];
    try
        fwrite(state.client, data, 'char');
    catch ME
        set(state.status, 'String', ['UDP send failed: ' ME.message], ...
            'ForegroundColor', [1 0.3 0.25]);
    end
end

function receive_datagram(~, udpObject, ~)
    if ~ishandle(fig)
        return;
    end
    state = guidata(fig);
    if ~state.running || isempty(udpObject) || ~isvalid(udpObject)
        return;
    end
    receivedAt = datetime('now', 'Format', 'yyyy-MM-dd HH:mm:ss.SSS');
    try
        byteCount = get(udpObject, 'BytesAvailable');
        if byteCount < 9
            return;
        end
        bytes = fread(udpObject, byteCount, 'uint8');
        [frameType, packet] = state.decode_frame(bytes);
        if frameType ~= 63 || ~isfield(packet, 'type') || packet.type ~= 63
            return;
        end
        process_packet(fig, packet, receivedAt);
    catch ME
        if ishandle(fig)
            state = guidata(fig);
            if ishandle(state.status)
                set(state.status, 'String', ['Packet parse failed: ' ME.message], ...
                    'ForegroundColor', [1 0.3 0.25]);
            end
        end
    end
end

function process_packet(~, packet, receivedAt)
    if ~ishandle(fig)
        return;
    end
    state = guidata(fig);
    required = {'ret_iq_array', 'pac_tx_cnt', 'pac_rx_cnt', ...
        'pac_rx_crc_ok_cnt', 'pac_rx_crc_err_cnt', 'rms'};
    if ~state.running || ~all(isfield(packet, required))
        return;
    end
    [iRaw, qRaw] = unpack_iq_array(packet.ret_iq_array);
    if isempty(iRaw)
        return;
    end
    iNormalized = iRaw ./ 150 ./ sqrt(2);
    qNormalized = qRaw ./ 150 ./ sqrt(2);
    symbols = iNormalized + 1i .* qNormalized;
    [evmRms, ~] = evmCalculator(symbols);
    [merDb, ~] = merCalculator(symbols);

    rxCount = double(packet.pac_rx_cnt);
    crcErrorCount = double(packet.pac_rx_crc_err_cnt);
    if isnan(state.last_rx_count)
        rxDelta = 0;
        crcErrorDelta = 0;
    else
        rxDelta = counter_delta(rxCount, state.last_rx_count);
        crcErrorDelta = counter_delta(crcErrorCount, state.last_crc_err_count);
    end
    state.session_rx_delta = state.session_rx_delta + rxDelta;
    state.session_crc_err_delta = state.session_crc_err_delta + crcErrorDelta;
    state.last_rx_count = rxCount;
    state.last_crc_err_count = crcErrorCount;
    if state.session_rx_delta > 0
        per = min(1, max(0, state.session_crc_err_delta / state.session_rx_delta));
    else
        per = 0;
    end
    if per >= 1
        berEstimate = 1;
    else
        berEstimate = 1 - (1 - per) .^ (1 / 108000);
    end

    packetNumber = numel(state.packet_records) + 1;
    elapsed = seconds(receivedAt - state.start_time);
    record = struct('packet_number', packetNumber, 'receive_time', receivedAt, ...
        'elapsed_seconds', elapsed, 'pac_tx_cnt', double(packet.pac_tx_cnt), ...
        'pac_rx_cnt', rxCount, 'pac_rx_crc_ok_cnt', double(packet.pac_rx_crc_ok_cnt), ...
        'pac_rx_crc_err_cnt', crcErrorCount, 'rms', double(packet.rms), ...
        'evm_rms_percent', double(evmRms), 'mer_db', double(merDb), ...
        'per', per, 'ber_estimate', berEstimate, 'i_raw', iRaw, 'q_raw', qRaw, ...
        'i_normalized', iNormalized, 'q_normalized', qNormalized);
    state.packet_records(end + 1) = record;

    set(state.constellation_line, 'XData', iNormalized, 'YData', qNormalized);
    packetCount = numel(state.packet_records);
    recent = state.packet_records(max(1, packetCount - 49):packetCount);
    x = [recent.elapsed_seconds];
    metricValues = {[recent.evm_rms_percent], [recent.per], ...
        [recent.ber_estimate], [recent.mer_db], [recent.rms]};
    for plotIndex = 1:5
        set(state.metric_lines(plotIndex), 'XData', x, 'YData', metricValues{plotIndex});
        if numel(x) == 1 || x(end) <= x(1)
            xlim(state.metric_axes(plotIndex), [max(0, x(end) - 1) x(end) + 1]);
        else
            xlim(state.metric_axes(plotIndex), [x(1) x(end)]);
        end
    end
    set(state.live_text, 'String', sprintf([ ...
        'Recorded packets: %d | I/Q points: %d | Tx: %.0f | Rx: %.0f | CRC OK: %.0f | CRC ERR: %.0f\n' ...
        'EVM RMS: %.3f %% | MER: %.3f dB | PER: %.4e | BER estimate: %.4e | Rx IF Power: %.3f dB'], ...
        packetCount, total_point_count(state.packet_records), ...
        double(packet.pac_tx_cnt), rxCount, double(packet.pac_rx_crc_ok_cnt), ...
        crcErrorCount, evmRms, merDb, per, berEstimate, double(packet.rms)));
    guidata(fig, state);
    drawnow limitrate;
end

function stop_capture(~, ~)
    if ~ishandle(fig)
        return;
    end
    state = guidata(fig);
    if ~state.running
        return;
    end
    state.running = false;
    stop_timer(state.request_timer);
    state.request_timer = [];
    close_client(state.client);
    state.client = [];
    set(state.start_button, 'Enable', 'on');
    set(state.stop_button, 'Enable', 'off');
    set(state.apply_ip_button, 'Enable', 'on');
    set(state.ip_edit, 'Enable', 'on');
    set(state.status, 'String', 'Saving capture ...', 'ForegroundColor', [1 0.7 0]);
    guidata(fig, state);
    try
        outputFolder = create_record_folder(state.output_root);
        [packetMetrics, constellationPoints, packetRecords, metadata] = ...
            build_record_tables(state.packet_records, state.start_time, ...
            datetime('now', 'Format', 'yyyy-MM-dd HH:mm:ss.SSS'), state.active_ip);
        save(fullfile(outputFolder, 'metrics_recording.mat'), ...
            'packetRecords', 'packetMetrics', 'constellationPoints', 'metadata', '-v7.3');
        writetable(packetMetrics, fullfile(outputFolder, 'packet_metrics.csv'));
        writetable(constellationPoints, fullfile(outputFolder, 'constellation_points.csv'));
        exportgraphics(fig, fullfile(outputFolder, 'dashboard.png'), 'Resolution', 150);
        state = guidata(fig);
        set(state.status, 'String', sprintf('Saved %d packets / %d points: %s', ...
            height(packetMetrics), height(constellationPoints), outputFolder), ...
            'ForegroundColor', [0.35 0.95 0.45]);
        guidata(fig, state);
    catch ME
        state = guidata(fig);
        set(state.status, 'String', ['Save failed: ' ME.message], ...
            'ForegroundColor', [1 0.3 0.25]);
        guidata(fig, state);
    end
end

function close_gui(hObject, ~)
    state = guidata(fig);
    if state.running
        stop_capture([], []);
    else
        stop_timer(state.request_timer);
        close_client(state.client);
    end
    if ishandle(hObject)
        delete(hObject);
    end
end

end

function [frameType, packet] = decode_metrics_frame(bytes)
bytes = double(bytes(:)');
if numel(bytes) < 9
    error('UDP message is shorter than the expected header.');
end
frameType = bytes(8);
messageLength = bytes(3) * 256 + bytes(4);
lastByte = min(numel(bytes), messageLength + 4);
if lastByte < 9
    lastByte = numel(bytes);
end
payload = char(bytes(9:lastByte));
payload = payload(payload ~= 0);
packet = jsondecode(strtrim(payload));
end

function [iRaw, qRaw] = unpack_iq_array(raw)
iRaw = zeros(0, 1);
qRaw = zeros(0, 1);
if isnumeric(raw)
    if size(raw, 2) >= 2
        iRaw = double(raw(:, 1));
        qRaw = double(raw(:, 2));
    end
elseif iscell(raw)
    if size(raw, 2) >= 2
        count = size(raw, 1);
        iRaw = zeros(count, 1);
        qRaw = zeros(count, 1);
        for k = 1:count
            iRaw(k) = unwrap_numeric_scalar(raw{k, 1});
            qRaw(k) = unwrap_numeric_scalar(raw{k, 2});
        end
    else
        count = numel(raw);
        iRaw = zeros(count, 1);
        qRaw = zeros(count, 1);
        for k = 1:count
            pair = raw{k};
            if iscell(pair)
                pair = cellfun(@unwrap_numeric_scalar, pair);
            end
            if numel(pair) < 2
                error('Each constellation entry must contain I and Q values.');
            end
            iRaw(k) = double(pair(1));
            qRaw(k) = double(pair(2));
        end
    end
end
if any(~isfinite(iRaw)) || any(~isfinite(qRaw))
    error('Constellation data contains non-finite I/Q values.');
end
end

function value = unwrap_numeric_scalar(value)
while iscell(value) && isscalar(value)
    value = value{1};
end
if ~isnumeric(value) || ~isscalar(value)
    error('Expected a numeric I/Q scalar.');
end
value = double(value);
end

function delta = counter_delta(current, previous)
delta = current - previous;
if delta < 0
    delta = max(current, 0);
end
end

function count = total_point_count(records)
if isempty(records)
    count = 0;
else
    count = sum(arrayfun(@(r) numel(r.i_raw), records));
end
end

function [packetMetrics, constellationPoints, packetRecords, metadata] = ...
        build_record_tables(records, startTime, endTime, deviceIP)
packetRecords = records;
packetCount = numel(records);
if packetCount == 0
    packet_number = zeros(0, 1);
    receive_time = NaT(0, 1);
    elapsed_seconds = zeros(0, 1);
    pac_tx_cnt = zeros(0, 1);
    pac_rx_cnt = zeros(0, 1);
    pac_rx_crc_ok_cnt = zeros(0, 1);
    pac_rx_crc_err_cnt = zeros(0, 1);
    rms = zeros(0, 1);
    evm_rms_percent = zeros(0, 1);
    mer_db = zeros(0, 1);
    per = zeros(0, 1);
    ber_estimate = zeros(0, 1);
else
    packet_number = [records.packet_number]';
    receive_time = [records.receive_time]';
    elapsed_seconds = [records.elapsed_seconds]';
    pac_tx_cnt = [records.pac_tx_cnt]';
    pac_rx_cnt = [records.pac_rx_cnt]';
    pac_rx_crc_ok_cnt = [records.pac_rx_crc_ok_cnt]';
    pac_rx_crc_err_cnt = [records.pac_rx_crc_err_cnt]';
    rms = [records.rms]';
    evm_rms_percent = [records.evm_rms_percent]';
    mer_db = [records.mer_db]';
    per = [records.per]';
    ber_estimate = [records.ber_estimate]';
end
packetMetrics = table(packet_number, receive_time, elapsed_seconds, pac_tx_cnt, ...
    pac_rx_cnt, pac_rx_crc_ok_cnt, pac_rx_crc_err_cnt, rms, evm_rms_percent, ...
    mer_db, per, ber_estimate);

pointCount = total_point_count(records);
point_packet_number = zeros(pointCount, 1);
point_number = zeros(pointCount, 1);
point_receive_time = NaT(pointCount, 1);
i_raw = zeros(pointCount, 1);
q_raw = zeros(pointCount, 1);
i_normalized = zeros(pointCount, 1);
q_normalized = zeros(pointCount, 1);
offset = 0;
for k = 1:packetCount
    pointLength = numel(records(k).i_raw);
    target = offset + (1:pointLength);
    point_packet_number(target) = records(k).packet_number;
    point_number(target) = (1:pointLength)';
    point_receive_time(target) = records(k).receive_time;
    i_raw(target) = records(k).i_raw;
    q_raw(target) = records(k).q_raw;
    i_normalized(target) = records(k).i_normalized;
    q_normalized(target) = records(k).q_normalized;
    offset = offset + pointLength;
end
constellationPoints = table(point_packet_number, point_number, point_receive_time, ...
    i_raw, q_raw, i_normalized, q_normalized, 'VariableNames', ...
    {'packet_number', 'point_number', 'receive_time', 'i_raw', 'q_raw', ...
    'i_normalized', 'q_normalized'});
if ~isempty(startTime) && ~isnat(startTime) && ~isempty(endTime) && ~isnat(endTime)
    durationSeconds = max(0, seconds(endTime - startTime));
else
    durationSeconds = 0;
end
metadata = struct('source_ip', deviceIP, 'source_port', 5001, ...
    'start_time', startTime, 'end_time', endTime, ...
    'duration_seconds', durationSeconds, 'packet_count', packetCount, ...
    'point_count', pointCount, 'ber_type', 'PER-derived estimate', ...
    'ber_packet_length_bits', 108000, ...
    'receive_time_definition', 'Computer UDP callback time; points in a packet share the time.');
end

function outputFolder = create_record_folder(outputRoot)
if ~exist(outputRoot, 'dir')
    mkdir(outputRoot);
end
stamp = char(datetime('now', 'Format', 'yyyyMMdd_HHmmss'));
baseName = ['constellation_' stamp];
outputFolder = fullfile(outputRoot, baseName);
suffix = 1;
while exist(outputFolder, 'dir')
    outputFolder = fullfile(outputRoot, sprintf('%s_%d', baseName, suffix));
    suffix = suffix + 1;
end
mkdir(outputFolder);
end

function close_client(client)
if isempty(client)
    return;
end
try
    if isvalid(client)
        if strcmpi(client.Status, 'open')
            fclose(client);
        end
        delete(client);
    end
catch
end
end

function stop_timer(timerHandle)
if isempty(timerHandle)
    return;
end
try
    if isvalid(timerHandle)
        stop(timerHandle);
        delete(timerHandle);
    end
catch
end
end

function data = int2asc2(value)
data = char([floor(value / 16) + 48, mod(value, 16) + 48]);
end

function deviceIP = get_saved_device_ip()
deviceIP = '192.168.0.27';
if ispref('XilingZU27DR', 'BoardIP')
    savedIP = getpref('XilingZU27DR', 'BoardIP');
    if is_valid_ipv4_address(savedIP)
        deviceIP = char(savedIP);
    end
end
end

function valid = is_valid_ipv4_address(ip)
valid = false;
if isstring(ip) && isscalar(ip)
    ip = char(ip);
end
if ~ischar(ip) || ~isrow(ip)
    return;
end
parts = regexp(strtrim(ip), '\.', 'split');
if numel(parts) ~= 4
    return;
end
for k = 1:4
    if isempty(regexp(parts{k}, '^(0|[1-9][0-9]{0,2})$', 'once'))
        return;
    end
    if str2double(parts{k}) > 255
        return;
    end
end
valid = true;
end
