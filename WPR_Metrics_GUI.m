function fig = WPR_Metrics_GUI()
% Real-time constellation and link-metric monitor for the ZU27DR board.

existing = findall(0, 'Type', 'figure', 'Tag', 'WPR_Metrics_GUI');
if ~isempty(existing)
    fig = existing(1);
    figure(fig);
    return;
end

deviceIP = get_saved_device_ip();
modulationConfig = get_modulation_config('QPSK');
screen = get(0, 'ScreenSize');
windowWidth = min(1480, screen(3) - 80);
windowHeight = min(900, screen(4) - 100);
left = max(20, (screen(3) - windowWidth) / 2);
bottom = max(30, (screen(4) - windowHeight) / 2);
fig = figure('Name', 'ZU27DR Metrics Monitor', 'NumberTitle', 'off', ...
    'MenuBar', 'none', 'Color', [0.02 0.02 0.02], ...
    'Position', [left bottom windowWidth windowHeight], 'Tag', 'WPR_Metrics_GUI', ...
    'CloseRequestFcn', @close_gui);

emptyRecords = struct('packet_number', {}, 'modulation', {}, 'receive_time', {}, ...
    'elapsed_seconds', {}, 'pac_tx_cnt', {}, 'pac_rx_cnt', {}, ...
    'pac_rx_crc_ok_cnt', {}, 'pac_rx_crc_err_cnt', {}, 'rms', {}, ...
    'evm_rms_percent', {}, 'mer_db', {}, 'per', {}, 'per_upper_95', {}, ...
    'per_sample_count', {}, 'per_error_count', {}, 'ber_estimate', {}, 'ber_upper_95', {}, ...
    'i_raw', {}, 'q_raw', {}, 'i_normalized', {}, 'q_normalized', {});
% Keep each callback's state local; guidata owns the current capture state.
initialState = struct('active_ip', deviceIP, 'running', false, 'saving', false, 'stopping', false, ...
    'modulation_config', modulationConfig, 'client', [], ...
    'request_timer', [], 'start_time', NaT, 'packet_records', emptyRecords, ...
    'pending_capture', [], 'last_output_folder', '', ...
    'last_rx_count', NaN, 'last_crc_err_count', NaN, ...
    'session_rx_delta', 0, 'session_crc_err_delta', 0, ...
    'output_root', fullfile(fileparts(mfilename('fullpath')), 'constellation_records'), ...
    'metric_lines', gobjects(5, 1), 'metric_axes', gobjects(5, 1), ...
    'metric_values', gobjects(5, 1), 'summary_values', gobjects(8, 1));
[evmCalculator, merCalculator] = create_metric_calculators(modulationConfig.reference_constellation);
initialState.process_packet = @(packet, receivedAt) process_packet(fig, packet, receivedAt);
initialState.stop_capture = @() stop_capture(fig);
initialState.save_capture = @() save_capture(fig, []);
initialState.decode_frame = @decode_metrics_frame;
guidata(fig, initialState);

initialState.modulation_group = uibuttongroup(fig, 'Title', 'Modulation (analysis)', ...
    'Units', 'normalized', 'Position', [0.025 0.926 0.28 0.065], ...
    'ForegroundColor', [0.85 0.9 0.85], 'BackgroundColor', [0.02 0.02 0.02], ...
    'FontSize', 9, 'Tag', 'WPR_Metrics_Modulation');
modulationNames = {'QPSK', '8PSK', '16QAM'};
initialState.modulation_buttons = gobjects(3, 1);
for modulationIndex = 1:numel(modulationNames)
    initialState.modulation_buttons(modulationIndex) = uicontrol(initialState.modulation_group, ...
        'Style', 'radiobutton', 'String', modulationNames{modulationIndex}, ...
        'Tag', modulationNames{modulationIndex}, 'Units', 'normalized', ...
        'Position', [0.025 + (modulationIndex - 1) * 0.325 0.05 0.32 0.8], ...
        'ForegroundColor', [0.85 0.9 0.85], ...
        'BackgroundColor', [0.02 0.02 0.02], 'FontSize', 10, ...
        'TooltipString', 'Match the board modulation; this selection only changes GUI analysis.');
end
set(initialState.modulation_group, 'SelectedObject', initialState.modulation_buttons(1), ...
    'SelectionChangedFcn', @select_modulation);
guidata(fig, initialState);

uicontrol(fig, 'Style', 'text', 'String', 'Board IP', ...
    'Units', 'normalized', 'Position', [0.32 0.932 0.055 0.045], ...
    'ForegroundColor', [0.85 0.9 0.85], 'BackgroundColor', [0.02 0.02 0.02], ...
    'HorizontalAlignment', 'left', 'FontSize', 10);
initialState = guidata(fig);
initialState.ip_edit = uicontrol(fig, 'Style', 'edit', 'String', deviceIP, ...
    'Units', 'normalized', 'Position', [0.377 0.932 0.14 0.047], ...
    'BackgroundColor', 'white', 'ForegroundColor', 'black', 'FontSize', 10, ...
    'Tag', 'WPR_Metrics_IP');
initialState.apply_ip_button = uicontrol(fig, 'Style', 'pushbutton', 'String', 'Apply IP', ...
    'Units', 'normalized', 'Position', [0.525 0.932 0.085 0.047], ...
    'FontSize', 10, 'Callback', @apply_ip);
initialState.start_button = uicontrol(fig, 'Style', 'pushbutton', 'String', 'START', ...
    'Units', 'normalized', 'Position', [0.625 0.932 0.09 0.047], ...
    'FontSize', 10, 'FontWeight', 'bold', 'Callback', @start_capture);
initialState.stop_button = uicontrol(fig, 'Style', 'pushbutton', 'String', 'STOP', ...
    'Units', 'normalized', 'Position', [0.73 0.932 0.09 0.047], ...
    'FontSize', 10, 'FontWeight', 'bold', 'Enable', 'off', ...
    'Callback', @stop_capture);
initialState.save_button = uicontrol(fig, 'Style', 'pushbutton', 'String', 'SAVE', ...
    'Units', 'normalized', 'Position', [0.845 0.932 0.115 0.047], ...
    'FontSize', 12, 'FontWeight', 'bold', 'Enable', 'off', ...
    'BackgroundColor', [0.72 0.72 0.72], 'ForegroundColor', [0.35 0.35 0.35], ...
    'TooltipString', 'Save the completed START-to-STOP capture.', 'Callback', @save_capture);
initialState.status = uicontrol(fig, 'Style', 'text', 'String', '就绪', ...
    'Units', 'normalized', 'Position', [0.035 0.885 0.93 0.03], ...
    'ForegroundColor', [0.35 0.95 0.45], 'BackgroundColor', [0.02 0.02 0.02], ...
    'HorizontalAlignment', 'left', 'FontSize', 11, 'Tag', 'WPR_Metrics_Status');
guidata(fig, initialState);

summaryPositions = [0.045 0.062 0.18 0.036; 0.235 0.062 0.18 0.036; ...
    0.425 0.062 0.21 0.036; 0.045 0.018 0.075 0.036; ...
    0.125 0.018 0.115 0.036; 0.245 0.018 0.115 0.036; ...
    0.365 0.018 0.14 0.036; 0.51 0.018 0.15 0.036];
for summaryIndex = 1:8
    initialState.summary_values(summaryIndex) = uicontrol(fig, 'Style', 'text', ...
        'Units', 'normalized', 'Position', summaryPositions(summaryIndex, :), ...
        'ForegroundColor', [0.8 0.85 0.9], 'BackgroundColor', [0.02 0.02 0.02], ...
        'HorizontalAlignment', 'left', 'FontSize', 11);
end
guidata(fig, initialState);

constellationAxes = axes('Parent', fig, 'Units', 'normalized', ...
    'Position', [0.045 0.155 0.56 0.64], 'Color', 'k', ...
    'XColor', [0.25 0.9 0.35], 'YColor', [0.25 0.9 0.35], ...
    'FontSize', 10, 'Box', 'on');
hold(constellationAxes, 'on');
initialState.constellation_line = plot(constellationAxes, NaN, NaN, '.', ...
    'Color', [1 0.7 0], 'MarkerSize', 9, 'Tag', 'WPR_Metrics_Constellation');
initialState.constellation_axes = constellationAxes;
reference = modulationConfig.reference_constellation;
initialState.reference_line = plot(constellationAxes, real(reference), imag(reference), 'r+', ...
    'LineWidth', 1.5, 'MarkerSize', 10, 'Tag', 'WPR_Metrics_Reference');
guidata(fig, initialState);
axis(constellationAxes, [-2 2 -2 2]);
axis(constellationAxes, 'square');
grid(constellationAxes, 'on');
set(constellationAxes, 'GridColor', [0.15 0.5 0.2]);
xlabel(constellationAxes, 'In-phase');
ylabel(constellationAxes, 'Quadrature');
title(constellationAxes, 'Constellation (QPSK)', 'Color', [0.25 0.9 0.35]);

metricNames = {'EVM RMS', 'PER · 95% 上限', '推算 BER · 95% 上限', 'MER', 'Rx IF Power'};
metricTips = {'EVM RMS in percent, using the selected reference constellation.', ...
    ['Pointwise 95% one-sided Clopper-Pearson upper bound; assumes independent packets with a constant error probability. ' ...
    'The first report sets the counter baseline; no statistical packets or inconsistent counters show --.'], ...
    ['Derived from the PER 95% upper bound using 108000 bits per packet and independent bit errors; ' ...
    'not directly measured BER.'], ...
    'MER in dB, using the selected reference constellation.', ...
    'Board-reported rms field in dB; this is not calibrated RSSI.'};
metricColors = [1 0.7 0; 1 0.3 0.25; 0.25 0.8 1; 0.25 0.9 0.45; 1 0.55 0.2];
metricY = [0.708 0.556 0.404 0.252 0.100];
for metricIndex = 1:numel(metricNames)
    plotHeight = 0.105;
    if metricIndex == 2
        plotHeight = 0.081; % Leave a separate line for K/N.
    end
    plotBottom = metricY(metricIndex);
    if metricIndex == 2 || metricIndex == 3
        plotBottom = plotBottom + 0.02;
        plotHeight = plotHeight - 0.02;
    end
    ax = axes('Parent', fig, 'Units', 'normalized', ...
        'Position', [0.665 plotBottom 0.29 plotHeight], 'Color', 'k', ...
        'XColor', [0.75 0.85 0.75], 'YColor', [0.75 0.85 0.75], ...
        'FontSize', 8, 'Box', 'on');
    hold(ax, 'on');
    lineHandle = plot(ax, NaN, NaN, 'LineWidth', 1.5, 'Color', metricColors(metricIndex, :));
    grid(ax, 'on');
    set(ax, 'GridColor', [0.15 0.35 0.18]);
    % Keep scientific notation on each tick, away from the metric heading.
    ax.YAxis.Exponent = 0;
    ytickformat(ax, '%g');
    if metricIndex == 2 || metricIndex == 3
        ax.XAxis.Exponent = 0;
        xtickformat(ax, '%.3g');
    end
    headerOffset = 0.001;
    headerHeight = 0.036;
    if metricIndex == 2
        headerOffset = headerOffset + 0.029;
    end
    headerPosition = [0.665 plotBottom + plotHeight + headerOffset 0.19 headerHeight];
    uicontrol(fig, 'Style', 'text', 'String', metricNames{metricIndex}, ...
        'Units', 'normalized', 'Position', headerPosition, ...
        'HorizontalAlignment', 'left', 'FontSize', 11, ...
        'BackgroundColor', [0.02 0.02 0.02], 'ForegroundColor', metricColors(metricIndex, :), ...
        'TooltipString', metricTips{metricIndex});
    initialState = guidata(fig);
    initialState.metric_values(metricIndex) = uicontrol(fig, 'Style', 'text', 'String', '--', ...
        'Units', 'normalized', 'Position', [0.855 headerPosition(2) 0.10 headerHeight], ...
        'HorizontalAlignment', 'right', 'FontSize', 12, ...
        'BackgroundColor', [0.02 0.02 0.02], 'ForegroundColor', metricColors(metricIndex, :), ...
        'TooltipString', metricTips{metricIndex});
    if metricIndex == 2
        initialState.per_details = uicontrol(fig, 'Style', 'text', ...
            'String', '本轮错包/收包 0/0', ...
            'Units', 'normalized', 'Position', [0.665 plotBottom + plotHeight + 0.001 0.30 0.028], ...
            'HorizontalAlignment', 'left', 'FontSize', 9, ...
            'BackgroundColor', [0.02 0.02 0.02], 'ForegroundColor', metricColors(metricIndex, :), ...
            'TooltipString', ['K/N uses cumulative changes in board pac_rx_crc_err_cnt/pac_rx_cnt since START, ' ...
            'not UDP report count or constellation point count. Board counter semantics require hardware verification.']);
    end
    if metricIndex == numel(metricNames)
        xlabel(ax, 'Time (s)', 'FontSize', 8);
    elseif metricIndex ~= 2 && metricIndex ~= 3
        set(ax, 'XTickLabel', []);
    end
    initialState.metric_axes(metricIndex) = ax;
    initialState.metric_lines(metricIndex) = lineHandle;
    guidata(fig, initialState);
end

clear_display(guidata(fig));

function select_modulation(~, event)
    state = guidata(fig);
    if state.running || state.saving || state.stopping
        selected = findobj(state.modulation_buttons, 'Tag', state.modulation_config.name);
        set(state.modulation_group, 'SelectedObject', selected);
        sync_modulation_buttons(state);
        return;
    end
    requestedConfig = get_modulation_config(get(event.NewValue, 'Tag'));
    release(evmCalculator);
    release(merCalculator);
    [evmCalculator, merCalculator] = create_metric_calculators(requestedConfig.reference_constellation);
    state.modulation_config = requestedConfig;
    sync_modulation_buttons(state);
    state.packet_records = state.packet_records([]);
    state.start_time = NaT;
    reference = requestedConfig.reference_constellation;
    set(state.reference_line, 'XData', real(reference), 'YData', imag(reference));
    title(state.constellation_axes, ['Constellation (' requestedConfig.name ')'], ...
        'Color', [0.25 0.9 0.35]);
    clear_display(state);
    show_idle_status(state, ['Analysis: ' requestedConfig.name]);
    guidata(fig, state);
end

function sync_modulation_buttons(state)
    % Keep all radio Values consistent when rejecting a queued selection.
    for button = state.modulation_buttons.'
        set(button, 'Value', strcmp(get(button, 'Tag'), state.modulation_config.name));
    end
end

function clear_display(state)
    set(state.constellation_line, 'XData', NaN, 'YData', NaN);
    for lineIndex = 1:numel(state.metric_lines)
        set(state.metric_lines(lineIndex), 'XData', NaN, 'YData', NaN);
        set(state.metric_axes(lineIndex), 'XLim', [0 1], 'YLimMode', 'auto');
    end
    set(state.metric_values, 'String', '--');
    set(state.per_details, 'String', '本轮错包/收包 0/0');
    update_summary(state, 0);
end

function update_summary(state, elapsed)
    packets = numel(state.packet_records);
    counts = zeros(1, 4);
    if packets > 0
        last = state.packet_records(end);
        counts = [last.pac_tx_cnt last.pac_rx_cnt last.pac_rx_crc_ok_cnt last.pac_rx_crc_err_cnt];
    end
    labels = {sprintf('UDP %d包', packets), ...
        sprintf('点 %d', total_point_count(state.packet_records)), ...
        sprintf('时长 %.2f s', max(0, elapsed)), ...
        '板卡累计', sprintf('Tx %.0f', counts(1)), sprintf('Rx %.0f', counts(2)), ...
        sprintf('CRC OK %.0f', counts(3)), sprintf('CRC ERR %.0f', counts(4))};
    for index = 1:8
        set(state.summary_values(index), 'String', labels{index});
    end
end

function update_save_button(state)
    if ~state.running && ~state.saving && ~isempty(state.pending_capture)
        set(state.save_button, 'Enable', 'on', 'BackgroundColor', [1 0.63 0.14], ...
            'ForegroundColor', [0.1 0.08 0.04]);
    else
        set(state.save_button, 'Enable', 'off', 'BackgroundColor', [0.72 0.72 0.72], ...
            'ForegroundColor', [0.35 0.35 0.35]);
    end
end

function show_idle_status(state, message)
    if ~isempty(state.pending_capture)
        message = ['已停止 · ' state.pending_capture.modulation_config.name ' 本轮数据未保存'];
        color = [1 0.7 0.25];
    else
        color = [0.35 0.95 0.45];
    end
    set(state.status, 'String', message, 'ForegroundColor', color);
end

function set_capture_controls(state, busy)
    if busy
        enabled = 'off';
    else
        enabled = 'on';
    end
    set([state.start_button; state.apply_ip_button; state.ip_edit; ...
        state.modulation_buttons(:)], 'Enable', enabled);
end

function apply_ip(~, ~)
    state = guidata(fig);
    if state.running || state.saving || state.stopping
        return;
    end
    requestedIP = strtrim(get(state.ip_edit, 'String'));
    if ~is_valid_ipv4_address(requestedIP)
        set(state.status, 'String', 'Invalid IPv4 address', ...
            'ForegroundColor', [1 0.3 0.25]);
        return;
    end
    state.active_ip = requestedIP;
    setpref('XilingZU27DR', 'BoardIP', requestedIP);
    show_idle_status(state, ['IP applied: ' requestedIP]);
    guidata(fig, state);
end

function start_capture(~, ~)
    state = guidata(fig);
    if state.running || state.saving || state.stopping
        return;
    end
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
    state.pending_capture = [];
    state.last_output_folder = '';
    state.start_time = datetime('now', 'Format', 'yyyy-MM-dd HH:mm:ss.SSS');
    state.last_rx_count = NaN;
    state.last_crc_err_count = NaN;
    state.session_rx_delta = 0;
    state.session_crc_err_delta = 0;
    clear_display(state);
    state.running = true;
    update_save_button(state);
    set_capture_controls(state, true);
    set(state.stop_button, 'Enable', 'on');
    set(state.status, 'String', ['Opening UDP to ' state.active_ip ':5001 ...'], ...
        'ForegroundColor', [1 0.7 0]);
    guidata(fig, state);

    client = [];
    timerHandle = [];
    try
        release(evmCalculator);
        release(merCalculator);
        [evmCalculator, merCalculator] = create_metric_calculators(state.modulation_config.reference_constellation);
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
        set_capture_controls(state, false);
        set(state.stop_button, 'Enable', 'off');
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
    iNormalized = iRaw ./ state.modulation_config.normalization_divisor;
    qNormalized = qRaw ./ state.modulation_config.normalization_divisor;
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
    [per, perUpper95] = calculate_per_statistics(state.session_rx_delta, state.session_crc_err_delta);
    % Keep BER tied to observed PER; log1p/expm1 preserve small probabilities.
    berEstimate = -expm1(log1p(-per) / 108000);
    berUpper95 = -expm1(log1p(-perUpper95) / 108000);

    packetNumber = numel(state.packet_records) + 1;
    elapsed = seconds(receivedAt - state.start_time);
    record = struct('packet_number', packetNumber, 'modulation', state.modulation_config.name, ...
        'receive_time', receivedAt, ...
        'elapsed_seconds', elapsed, 'pac_tx_cnt', double(packet.pac_tx_cnt), ...
        'pac_rx_cnt', rxCount, 'pac_rx_crc_ok_cnt', double(packet.pac_rx_crc_ok_cnt), ...
        'pac_rx_crc_err_cnt', crcErrorCount, 'rms', double(packet.rms), ...
        'evm_rms_percent', double(evmRms), 'mer_db', double(merDb), ...
        'per', per, 'per_upper_95', perUpper95, ...
        'per_sample_count', state.session_rx_delta, 'per_error_count', state.session_crc_err_delta, ...
        'ber_estimate', berEstimate, 'ber_upper_95', berUpper95, 'i_raw', iRaw, 'q_raw', qRaw, ...
        'i_normalized', iNormalized, 'q_normalized', qNormalized);
    state.packet_records(end + 1) = record;

    set(state.constellation_line, 'XData', iNormalized, 'YData', qNormalized);
    packetCount = numel(state.packet_records);
    recent = state.packet_records(max(1, packetCount - 49):packetCount);
    allRecords = state.packet_records;
    metricRecords = {recent, allRecords, allRecords, recent, recent};
    metricValues = {[recent.evm_rms_percent], [allRecords.per_upper_95], ...
        [allRecords.ber_upper_95], [recent.mer_db], [recent.rms]};
    for plotIndex = 1:5
        x = [metricRecords{plotIndex}.elapsed_seconds];
        set(state.metric_lines(plotIndex), 'XData', x, 'YData', metricValues{plotIndex});
        if plotIndex == 2 || plotIndex == 3
            if x(end) > 0
                xlim(state.metric_axes(plotIndex), [0 x(end)]);
            else
                xlim(state.metric_axes(plotIndex), [0 1]);
            end
            limits = xlim(state.metric_axes(plotIndex));
            xticks(state.metric_axes(plotIndex), linspace(limits(1), limits(2), 5));
        elseif numel(x) == 1 || x(end) <= x(1)
            xlim(state.metric_axes(plotIndex), [max(0, x(end) - 1) x(end) + 1]);
        else
            xlim(state.metric_axes(plotIndex), [x(1) x(end)]);
        end
    end
    values = {sprintf('%.3f %%', evmRms), format_probability(perUpper95), ...
        format_probability(berUpper95), sprintf('%.3f dB', merDb), sprintf('%.3f dB', double(packet.rms))};
    for index = 1:5
        set(state.metric_values(index), 'String', values{index});
    end
    if isnan(per) && (state.session_rx_delta ~= 0 || state.session_crc_err_delta ~= 0)
        detail = sprintf('计数异常  本轮错包/收包 %.0f/%.0f', ...
            state.session_crc_err_delta, state.session_rx_delta);
    else
        detail = sprintf('本轮错包/收包 %.0f/%.0f', ...
            state.session_crc_err_delta, state.session_rx_delta);
    end
    set(state.per_details, 'String', detail);
    update_summary(state, elapsed);
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
    state.stopping = true;
    endTime = datetime('now', 'Format', 'yyyy-MM-dd HH:mm:ss.SSS');
    guidata(fig, state);
    stop_timer(state.request_timer);
    state.request_timer = [];
    close_client(state.client);
    state.client = [];
    set(state.stop_button, 'Enable', 'off');
    update_summary(state, seconds(endTime - state.start_time));
    if isempty(state.packet_records)
        state.pending_capture = [];
        set(state.status, 'String', '已停止 · 未收到有效数据', 'ForegroundColor', [1 0.7 0.25]);
    else
        state.pending_capture = struct('packet_records', state.packet_records, ...
            'start_time', state.start_time, 'end_time', endTime, ...
            'active_ip', state.active_ip, 'modulation_config', state.modulation_config, ...
            'dashboard_image', []);
        set(state.status, 'String', '已停止 · 本轮数据未保存', 'ForegroundColor', [1 0.7 0.25]);
    end
    % Callbacks remain guarded by stopping while print processes graphics events.
    set_capture_controls(state, false);
    update_save_button(state);
    guidata(fig, state);
    if ~isempty(state.pending_capture)
        try
            set(fig, 'InvertHardcopy', 'off', 'PaperPositionMode', 'auto');
            sync_modulation_buttons(state);
            refresh(fig);
            drawnow;
            % R2023b caches native radio glyphs between hidden-window prints.
            % Prime that cache so this snapshot uses the current selection.
            print(fig, '-RGBImage', '-r150');
            dashboardImage = print(fig, '-RGBImage', '-r150');
            state = guidata(fig);
            state.pending_capture.dashboard_image = dashboardImage;
        catch ME
            state = guidata(fig);
            set(state.status, 'String', ['Stop image capture failed: ' ME.message], ...
                'ForegroundColor', [1 0.3 0.25]);
        end
    end
    state.stopping = false;
    guidata(fig, state);
end

function save_capture(~, ~)
    if ~ishandle(fig)
        return;
    end
    state = guidata(fig);
    if state.running || state.saving || state.stopping || isempty(state.pending_capture)
        return;
    end
    capture = state.pending_capture;
    state.saving = true;
    set_capture_controls(state, true);
    update_save_button(state);
    guidata(fig, state);
    set(state.status, 'String', 'Saving capture ...', 'ForegroundColor', [1 0.7 0]);
    try
        if isempty(capture.dashboard_image)
            error('WPR:MissingSnapshot', 'The stopped dashboard image is unavailable; capture data remains in memory.');
        end
        outputFolder = create_record_folder(state.output_root);
        [packetMetrics, constellationPoints, metadata] = ...
            build_record_data(capture.packet_records, capture.start_time, capture.end_time, ...
            capture.active_ip, capture.modulation_config);
        save(fullfile(outputFolder, 'metrics_recording.mat'), ...
            'constellationPoints', 'packetMetrics', 'metadata', '-v7.3');
        imwrite(capture.dashboard_image, fullfile(outputFolder, 'dashboard.png'));
        state = guidata(fig);
        state.pending_capture = [];
        state.last_output_folder = outputFolder;
        set(state.status, 'String', sprintf('已保存 %d 包 / %d 个点', ...
            metadata.packet_count, metadata.point_count), ...
            'ForegroundColor', [0.35 0.95 0.45]);
        set(state.status, 'TooltipString', outputFolder);
        guidata(fig, state);
    catch ME
        state = guidata(fig);
        set(state.status, 'String', ['Save failed: ' ME.message], ...
            'ForegroundColor', [1 0.3 0.25]);
        guidata(fig, state);
    end
    state = guidata(fig);
    state.saving = false;
    set_capture_controls(state, false);
    update_save_button(state);
    guidata(fig, state);
end

function close_gui(hObject, ~)
    state = guidata(fig);
    if state.saving || state.stopping
        return;
    end
    stop_timer(state.request_timer);
    close_client(state.client);
    release(evmCalculator);
    release(merCalculator);
    if ishandle(hObject)
        delete(hObject);
    end
end

end

function config = get_modulation_config(name)
% Analysis defaults only: confirm gain and phase against the actual board.
switch name
    case 'QPSK'
        order = 4;
        phaseOffset = pi / 4;
        reference = qammod(0:3, 4, 'gray', 'UnitAveragePower', true);
    case '8PSK'
        order = 8;
        phaseOffset = pi / 8;
        reference = pskmod(0:7, 8, phaseOffset, 'gray');
    case '16QAM'
        order = 16;
        phaseOffset = 0;
        reference = qammod(0:15, 16, 'gray', 'UnitAveragePower', true);
    otherwise
        error('Unsupported modulation: %s', name);
end
config = struct('name', name, 'order', order, ...
    'reference_constellation', reference(:), 'phase_offset_rad', phaseOffset, ...
    'normalization_divisor', 150 * sqrt(2));
end

function [evmCalculator, merCalculator] = create_metric_calculators(reference)
evmCalculator = comm.EVM('MaximumEVMOutputPort', true, ...
    'ReferenceSignalSource', 'Estimated from reference constellation', ...
    'ReferenceConstellation', reference);
merCalculator = comm.MER('MinimumMEROutputPort', true, ...
    'ReferenceSignalSource', 'Estimated from reference constellation', ...
    'ReferenceConstellation', reference);
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

function [observed, upper95] = calculate_per_statistics(sampleCount, errorCount)
% Exact one-sided, pointwise binomial bound, including nonzero error counts.
observed = NaN;
upper95 = NaN;
if ~isfinite(sampleCount) || ~isfinite(errorCount) || sampleCount <= 0 || ...
        errorCount < 0 || errorCount > sampleCount || ...
        sampleCount ~= fix(sampleCount) || errorCount ~= fix(errorCount)
    return;
end
observed = errorCount / sampleCount;
if errorCount == 0
    upper95 = -expm1(log(0.05) / sampleCount);
elseif errorCount == sampleCount
    upper95 = 1;
else
    upper95 = betaincinv(0.95, errorCount + 1, sampleCount - errorCount);
end
end

function label = format_probability(value)
if isfinite(value)
    label = sprintf('%.4e', value);
else
    label = '--';
end
end

function count = total_point_count(records)
if isempty(records)
    count = 0;
else
    count = sum(arrayfun(@(r) numel(r.i_raw), records));
end
end

function [packetMetrics, constellationPoints, metadata] = ...
        build_record_data(records, startTime, endTime, deviceIP, modulationConfig)
% Use plain structs and numeric arrays so HDF5 readers can read the MAT file.
packetCount = numel(records);
packetMetrics = struct('packet_number', [records.packet_number]', ...
    'receive_time', char(format_record_times([records.receive_time]')), ...
    'elapsed_seconds', [records.elapsed_seconds]', ...
    'pac_tx_cnt', [records.pac_tx_cnt]', 'pac_rx_cnt', [records.pac_rx_cnt]', ...
    'pac_rx_crc_ok_cnt', [records.pac_rx_crc_ok_cnt]', ...
    'pac_rx_crc_err_cnt', [records.pac_rx_crc_err_cnt]', ...
    'rx_if_power', [records.rms]', 'evm_rms_percent', [records.evm_rms_percent]', ...
    'mer_db', [records.mer_db]', 'per', [records.per]', ...
    'per_upper_95', [records.per_upper_95]', ...
    'per_sample_count', [records.per_sample_count]', ...
    'per_error_count', [records.per_error_count]', ...
    'ber_estimate', [records.ber_estimate]', 'ber_upper_95', [records.ber_upper_95]');

pointCounts = arrayfun(@(record) numel(record.i_raw), records(:));
% Row k indexes the same UDP report in both structs; starts use MATLAB indexing.
constellationPoints = struct('packet_start_index', [1; 1 + cumsum(pointCounts(1:end-1))], ...
    'point_count', pointCounts, 'i_raw', vertcat(records.i_raw), ...
    'q_raw', vertcat(records.q_raw));

metadata = struct('format_version', 1, 'source_ip', deviceIP, 'source_port', 5001, ...
    'start_time', format_record_time(startTime), 'end_time', format_record_time(endTime), ...
    'duration_seconds', max(0, seconds(endTime - startTime)), ...
    'packet_count', packetCount, 'point_count', sum(pointCounts), ...
    'ber_type', 'Observed-PER-derived estimate', 'ber_packet_length_bits', 108000, ...
    'ber_model_assumptions', 'Independent equally likely bit errors; any bit error causes a packet error.', ...
    'ber_upper_95_definition', ['Derived from per_upper_95 as -expm1(log1p(-per_upper_95)/108000); ' ...
    'pointwise 95% upper bound under the stated packet and bit error assumptions, not measured BER.'], ...
    'per_confidence_level', 0.95, 'per_upper_method', 'One-sided Clopper-Pearson', ...
    'per_confidence_scope', 'Pointwise at a fixed sample count; not a time-uniform confidence sequence.', ...
    'per_model_assumptions', 'Independent packets with a constant error probability.', ...
    'per_counter_basis', 'Cumulative pac_rx_crc_err_cnt/pac_rx_cnt deltas after the first report; not UDP report or I/Q point counts.', ...
    'per_counter_basis_verified', false, ...
    'modulation', modulationConfig.name, 'modulation_order', modulationConfig.order, ...
    'reference_constellation', modulationConfig.reference_constellation, ...
    'reference_phase_offset_rad', modulationConfig.phase_offset_rad, ...
    'normalization_divisor', modulationConfig.normalization_divisor, ...
    'normalization_definition', '(i_raw + 1i*q_raw) / normalization_divisor; no gain or phase fitting.', ...
    'board_modulation_controlled', false, ...
    'rx_if_power_definition', 'Board-provided rms; not calibrated RSSI.', ...
    'point_storage_definition', ['Native I/Q numeric arrays; packet_start_index is 1-based. ' ...
    'Row k of packet_start_index/point_count matches row k of packetMetrics. ' ...
    'Normalized I/Q is reconstructed using normalization_divisor.'], ...
    'receive_time_definition', ['Computer UDP callback local time; yyyy-MM-dd HH:mm:ss.SSS char matrix ' ...
    'with one row per UDP report; points in a report share the time.']);
end

function formatted = format_record_times(times)
times = times(:);
if isempty(times)
    formatted = strings(0, 1);
    return;
end
times.Format = 'yyyy-MM-dd HH:mm:ss.SSS';
formatted = string(times);
end

function formatted = format_record_time(timeValue)
if isempty(timeValue) || isnat(timeValue)
    formatted = '';
    return;
end
timeValue.Format = 'yyyy-MM-dd HH:mm:ss.SSS';
formatted = char(string(timeValue));
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
