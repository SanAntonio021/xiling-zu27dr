function fig = WPR_Metrics_Preview()
% Preview the real stopped dashboard with synthetic data and no UDP objects.
if ~isempty(findall(0, 'Type', 'figure', 'Tag', 'WPR_Metrics_GUI'))
    error('WPR:PreviewWindowExists', ...
        '请先关闭已打开的采集界面，再运行 WPR_Metrics_Preview；已有数据不会被覆盖。');
end

fig = WPR_Metrics_GUI;
set(fig, 'Name', 'ZU27DR Metrics Monitor - 离线预览（模拟数据）');
state = guidata(fig);
state.active_ip = 'OFFLINE_PREVIEW';
state.output_root = fullfile(fileparts(mfilename('fullpath')), '过程文件', '界面离线预览');
state.start_time = datetime('now', 'Format', 'yyyy-MM-dd HH:mm:ss.SSS') - seconds(10);
state.running = true;
set(state.ip_edit, 'String', 'OFFLINE_PREVIEW');
set([state.start_button; state.apply_ip_button], 'Callback', @preview_notice);
title(state.constellation_axes, 'Constellation (QPSK) · 模拟数据', ...
    'Color', [0.25 0.9 0.35]);
guidata(fig, state);

reference = state.modulation_config.reference_constellation;
pointIndex = (0:499)';
ideal = reference(mod(pointIndex, numel(reference)) + 1);
for report = 0:50
    noise = (0.018 + 0.006 * sin(report / 5)) * ...
        (sin(pointIndex * 1.37 + report) + 1i * cos(pointIndex * 1.91 + report));
    raw = (ideal + noise) * state.modulation_config.normalization_divisor;
    rxCount = 100000 + report * 1200;
    packet = struct('type', 63, 'pac_tx_cnt', rxCount + 1, ...
        'pac_rx_cnt', rxCount, 'pac_rx_crc_ok_cnt', rxCount, ...
        'pac_rx_crc_err_cnt', 0, 'rms', -31.25 + 0.5 * sin(report / 7), ...
        'ret_iq_array', [real(raw) imag(raw)]);
    state.process_packet(packet, state.start_time + seconds(report / 5));
end
state.stop_capture();
preview_notice();

    function preview_notice(~, ~)
        current = guidata(fig);
        set(current.status, 'String', '离线预览 · 模拟数据，可填写名称并试用 SAVE', ...
            'ForegroundColor', [1 0.7 0.25]);
    end
end
