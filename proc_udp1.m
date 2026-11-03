function proc_udp1(udp_obj, event)
global recvbuf num sum_recv recv_state pac_rx_cnt_initial pac_rx_crc_err_cnt_initial
global g_handles
global i_data
global q_data
global recording_active constellation_recording recording_packet_count

packet_receive_time = now;
bytesAvailable = get(udp_obj, 'BytesAvailable');
if bytesAvailable < 8
    return;
end
recvbuf = fread(udp_obj, bytesAvailable, 'char');
msg_len = recvbuf(3) * 16 * 16 + recvbuf(4);
frame_type = recvbuf(8);
data_string_recv_data = recvbuf(9:msg_len + 9 - 4 - 1);
req_str = parse_json(char(data_string_recv_data)');
json_type = req_str.type;
if frame_type == 2
    recv_state = 1;
    return;
end
if frame_type == 63 && json_type == 63
    num = num + 1;
end
%% display
set(g_handles.text_RECV_NUM,'string', num);

pac_tx_cnt = req_str.pac_tx_cnt;
pac_rx_cnt = req_str.pac_rx_cnt;
pac_rx_crc_ok_cnt = req_str.pac_rx_crc_ok_cnt;
pac_rx_crc_err_cnt = req_str.pac_rx_crc_err_cnt;
rms = req_str.rms;
ber = 0;
if num == 1
    pac_rx_cnt_initial = pac_rx_cnt;
    pac_rx_crc_err_cnt_initial =  pac_rx_crc_err_cnt;
end

if pac_rx_cnt-pac_rx_cnt_initial > 0
    ber = (pac_rx_crc_err_cnt-pac_rx_crc_err_cnt_initial) / (pac_rx_cnt-pac_rx_cnt_initial);
end

set(g_handles.text_PAC_TX,'string',strcat('0x',dec2hex(pac_tx_cnt)));
set(g_handles.text_PAC_RX,'string',strcat('0x',dec2hex(pac_rx_cnt)));
set(g_handles.text_CRC_OK,'string',strcat('0x',dec2hex(pac_rx_crc_ok_cnt)));
set(g_handles.text_CRC_ERR,'string',strcat('0x',dec2hex(pac_rx_crc_err_cnt)));
set(g_handles.text_WUBAO,'string',ber);
set(g_handles.text_rssi, 'string', rms);

iq_arr = req_str.ret_iq_array;
L = size(iq_arr , 2);
i_packet = zeros(L,1);
q_packet = zeros(L,1);
for k = 1:L
    i_packet(k) = iq_arr{k}{1};
    q_packet(k) = iq_arr{k}{2};
end
i_data(1:L) = i_packet;
q_data(1:L) = q_packet;

if isempty(recording_packet_count)
    recording_packet_count = 0;
end
if isempty(constellation_recording)
    constellation_recording = struct('packet_number', zeros(0,1), ...
        'point_number', zeros(0,1), ...
        'receive_time_datenum', zeros(0,1), ...
        'i', zeros(0,1), 'q', zeros(0,1));
end
if recording_active && L > 0
    recording_packet_count = recording_packet_count + 1;
    constellation_recording.packet_number = [constellation_recording.packet_number; repmat(recording_packet_count,L,1)];
    constellation_recording.point_number = [constellation_recording.point_number; (1:L)'];
    constellation_recording.receive_time_datenum = [constellation_recording.receive_time_datenum; repmat(packet_receive_time,L,1)];
    constellation_recording.i = [constellation_recording.i; i_packet];
    constellation_recording.q = [constellation_recording.q; q_packet];
end

if L > 0
    plot(g_handles.axes_PlotMap, i_data(1:L), q_data(1:L), 'r.', 'MarkerSize', 10);
    g_handles.axes_PlotMap.XLim=[-512,512];
    g_handles.axes_PlotMap.YLim=[-512,512];
end
end
