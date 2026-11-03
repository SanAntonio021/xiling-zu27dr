function varargout = WPR_GUI(varargin)
% WPR_GUI MATLAB code for WPR_GUI.fig
%      WPR_GUI, by itself, creates a new WPR_GUI or raises the existing
%      singleton*.
%

%      H = WPR_GUI returns the handle to a new WPR_GUI or the handle to
%      the existing singleton*.
%
%      WPR_GUI('CALLBACK',hObject,eventData,handles,...) calls the local
%      function named CALLBACK in WPR_GUI.M with the given input arguments.
%
%      WPR_GUI('Property','Value',...) creates a new WPR_GUI or raises the
%      existing singleton*.  Starting from the left, property value pairs are
%      applied to the GUI before WPR_GUI_OpeningFcn gets called.  An
%      unrecognized property name or invalid value makes property application
%      stop.  All inputs are passed to WPR_GUI_OpeningFcn via varargin.
%
%      *See GUI Options on GUIDE's Tools menu.  Choose "GUI allows only one
%      instance to run (singleton)".
%
% See also: GUIDE, GUIDATA, GUIHANDLES

% Edit the above text to modify the response to help WPR_GUI

% Last Modified by GUIDE v2.5 08-Dec-2022 10:39:47

% Begin initialization code - DO NOT EDIT
gui_Singleton = 1;
gui_State = struct('gui_Name',       mfilename, ...
    'gui_Singleton',  gui_Singleton, ...
    'gui_OpeningFcn', @WPR_GUI_OpeningFcn, ...
    'gui_OutputFcn',  @WPR_GUI_OutputFcn, ...
    'gui_LayoutFcn',  [] , ...
    'gui_Callback',   []);
if nargin && ischar(varargin{1})
    gui_State.gui_Callback = str2func(varargin{1});
end

if nargout
    [varargout{1:nargout}] = gui_mainfcn(gui_State, varargin{:});
else
    gui_mainfcn(gui_State, varargin{:});
end
% End initialization code - DO NOT EDIT


% --- Executes just before WPR_GUI is made visible.
function WPR_GUI_OpeningFcn(hObject, eventdata, handles, varargin)
% This function has no output args, see OutputFcn.
% hObject    handle to figure
% eventdata  reserved - to be defined in a future version of MATLAB
% handles    structure with handles and user data (see GUIDATA)
% varargin   command line arguments to WPR_GUI (see VARARGIN)

% Choose default command line output for WPR_GUI
handles.output = hObject;

global recording_active constellation_recording recording_start_time recording_end_time recording_packet_count
recording_active = false;
constellation_recording = struct('packet_number', zeros(0,1), ...
    'point_number', zeros(0,1), ...
    'receive_time_datenum', zeros(0,1), ...
    'i', zeros(0,1), 'q', zeros(0,1));
recording_start_time = [];
recording_end_time = [];
recording_packet_count = 0;
handles.tBTN_PlotMap = uicontrol('Parent', hObject, ...
    'Style', 'togglebutton', ...
    'String', 'START', ...
    'Units', 'characters', ...
    'Position', [122, 1.2, 34, 5], ...
    'FontSize', 10, ...
    'FontWeight', 'bold', ...
    'Tag', 'tBTN_PlotMap', ...
    'Callback', @(src, event) tBTN_PlotMap_Callback(src, event, guidata(src)));

%% Log_UESTC
position = get(handles.BTN_logUESTC,'Position');
image = imread('Log_UESTC.jpg');   %读取图片 Log_UESTC.png
image = imresize(image, [position(4)*2.85*5, position(3)*5]);
set(handles.BTN_logUESTC,'CData',image);

%% Global receivr_data
global t_client
% Find a udp object.
t_client = instrfind('Type', 'udp', 'RemoteHost', '192.168.0.27', 'RemotePort', 5001, 'Tag', '');

% Create the udp object if it does not exist
% otherwise use the object that was found.
if isempty(t_client)
    t_client = udp('192.168.0.27', 5001);
else
    fclose(t_client);
    t_client = t_client(1);
end

% t_client=udp('192.168.0.28','RemotePort',5001);
t_client.inputbuffersize = 1024*100;
t_client.OutputBuffersize = 8192;
t_client.DatagramReceivedFcn = @proc_udp1;
t_client.EnablePortSharing = 'on';
fopen(t_client);

% Update handles structure
guidata(hObject, handles);

% UIWAIT makes WPR_GUI wait for user response (see UIRESUME)
% uiwait(handles.figure1);


% --- Outputs from this function are returned to the command line.
function varargout = WPR_GUI_OutputFcn(hObject, eventdata, handles)
% varargout  cell array for returning output args (see VARARGOUT);
% hObject    handle to figure
% eventdata  reserved - to be defined in a future version of MATLAB
% handles    structure with handles and user data (see GUIDATA)

% Get default command line output from handles structure
varargout{1} = handles.output;


% --- Executes during object creation, after setting all properties.
function text_ETH_TX_CreateFcn(hObject, eventdata, handles)
% hObject    handle to text_ETH_TX (see GCBO)
% eventdata  reserved - to be defined in a future version of MATLAB
% handles    empty - handles not created until after all CreateFcns called

% Hint: edit controls usually have a white background on Windows.
%       See ISPC and COMPUTER.
if ispc && isequal(get(hObject,'BackgroundColor'), get(0,'defaultUicontrolBackgroundColor'))
    set(hObject,'BackgroundColor','white');
end

% --- Executes during object creation, after setting all properties.
function text_ETH_RX_CreateFcn(hObject, eventdata, handles)
% hObject    handle to text_ETH_RX (see GCBO)
% eventdata  reserved - to be defined in a future version of MATLAB
% handles    empty - handles not created until after all CreateFcns called

% Hint: edit controls usually have a white background on Windows.
%       See ISPC and COMPUTER.
if ispc && isequal(get(hObject,'BackgroundColor'), get(0,'defaultUicontrolBackgroundColor'))
    set(hObject,'BackgroundColor','white');
end

% --- Executes on button press in BTN_logUESTC.
function BTN_logUESTC_Callback(hObject, eventdata, handles)
% hObject    handle to BTN_logUESTC (see GCBO)
% eventdata  reserved - to be defined in a future version of MATLAB
% handles    structure with handles and user data (see GUIDATA)


% --- Executes on button press in tBTN_CtrlCon.
function tBTN_CtrlCon_Callback(hObject, eventdata, handles)
% hObject    handle to tBTN_CtrlCon (see GCBO)
% eventdata  reserved - to be defined in a future version of MATLAB
% handles    structure with handles and user data (see GUIDATA)
global t_client
if(get(handles.tBTN_CtrlCon,'value') == 1)
    fopen(t_client);
    set(handles.tBTN_CtrlCon,'string','设备已连接');
    set(handles.tBTN_CtrlCon,'BackgroundColor','g');
else
    fclose(t_client);
    set(handles.tBTN_CtrlCon,'string','设备已断开');
    set(handles.tBTN_CtrlCon,'BackgroundColor','r');
end
% Hint: get(hObject,'Value') returns toggle state of tBTN_CtrlCon



% --- Executes on button press in BTN_SYS.
function BTN_SYS_Callback(hObject, eventdata, handles)
% hObject    handle to BTN_SYS (see GCBO)
% eventdata  reserved - to be defined in a future version of MATLAB
% handles    structure with handles and user data (see GUIDATA)
set(handles.text_SYS,'BackgroundColor','r');

global t_client
global recv_state

global i_data
global q_data
% dispatcher use
global recvbuf num sum_recv
global g_handles

g_handles = handles;
handles.axes_PlotMap.XLim=[-512,512];
handles.axes_PlotMap.YLim=[-512,512];

i_data = zeros(1000,1);
q_data = zeros(1000,1);
recvbuf = zeros(30000,1);
num = 0;
sum_recv = 0;
    
    
recv_state = 0;
try_cnt = 0;
s = fileread('Handshaking.json');
data_send = [int2asc2(length(s)+4),int2asc2(1),s];
fwrite(t_client,data_send,'char');
set(handles.BTN_SYS,'string','linking....');
pause(1);
while(1)
    pause(0.5);
    if(recv_state == 1)
        set(handles.text_SYS,'BackgroundColor','g');
        set(handles.BTN_SYS,'string','linked');
        break
    else
        set(handles.text_SYS,'BackgroundColor','r');
        fwrite(t_client,data_send,'char');
        try_cnt = try_cnt + 1;
        if try_cnt == 10
            set(handles.BTN_SYS,'string','try once more');
            break;
        end
    end
end

% --- Executes on button press in tBTN_PlotMap.
function tBTN_PlotMap_Callback(hObject, eventdata, handles)
% hObject    handle to tBTN_PlotMap (see GCBO)
% eventdata  reserved - to be defined in a future version of MATLAB
% handles    structure with handles and user data (see GUIDATA)

% Hint: get(hObject,'Value') returns toggle state of tBTN_PlotMap
% global i_data
% global q_data
% global t_client
% 
% % dispatcher use
% global recvbuf num sum_recv
% global g_handles
% 
% g_handles = handles;
% handles.axes_PlotMap.XLim=[-512,512];
% handles.axes_PlotMap.YLim=[-512,512];
% 
% i_data = zeros(100,1);
% q_data = zeros(100,1);
% recvbuf = zeros(20000,1);
% num = 0;
% sum_recv = 0;
global recording_active constellation_recording recording_start_time recording_end_time recording_packet_count
global t_client

button_text = get(handles.tBTN_PlotMap, 'string');
if strcmpi(button_text, 'START')
    constellation_recording = struct('packet_number', zeros(0,1), ...
        'point_number', zeros(0,1), ...
        'receive_time_datenum', zeros(0,1), ...
        'i', zeros(0,1), 'q', zeros(0,1));
    recording_packet_count = 0;
    recording_start_time = now;
    recording_end_time = [];
    recording_active = true;

    s = fileread('Constellation.json');
    data_send = [int2asc2(length(s)+4),int2asc2(61),s];
    fwrite(t_client,data_send,'char');
    set(handles.tBTN_PlotMap,'string','STOP');
    set(handles.tBTN_PlotMap,'value',1);
else
    recording_active = false;
    recording_end_time = now;
    set(handles.tBTN_PlotMap,'string','START');
    set(handles.tBTN_PlotMap,'value',0);

    output_root = fullfile(fileparts(mfilename('fullpath')), 'constellation_records');
    if ~exist(output_root, 'dir')
        mkdir(output_root);
    end
    folder_name = ['constellation_' datestr(recording_end_time, 'yyyymmdd_HHMMSS')];
    output_folder = fullfile(output_root, folder_name);
    suffix = 1;
    while exist(output_folder, 'dir')
        output_folder = fullfile(output_root, [folder_name '_' num2str(suffix)]);
        suffix = suffix + 1;
    end
    mkdir(output_folder);

    point_count = length(constellation_recording.i);
    elapsed_seconds = (recording_end_time - recording_start_time) * 24 * 3600;
    if isempty(recording_start_time) || elapsed_seconds < 0
        elapsed_seconds = 0;
    end
    if elapsed_seconds > 0
        average_point_rate = point_count / elapsed_seconds;
    else
        average_point_rate = 0;
    end
    recording_meta = struct('start_time', recording_start_time, ...
        'end_time', recording_end_time, ...
        'point_count', point_count, ...
        'packet_count', recording_packet_count, ...
        'duration_seconds', elapsed_seconds, ...
        'average_point_rate', average_point_rate, ...
        'source_ip', '192.168.0.27', ...
        'source_port', 5001);

    save(fullfile(output_folder, 'constellation_recording.mat'), ...
        'constellation_recording', 'recording_meta');

    csv_path = fullfile(output_folder, 'constellation_points.csv');
    fid = fopen(csv_path, 'w');
    if fid < 0
        error('Cannot create CSV file: %s', csv_path);
    end
    fprintf(fid, 'packet_number,point_number,receive_time,i,q\n');
    for k = 1:point_count
        fprintf(fid, '%d,%d,"%s",%.17g,%.17g\n', ...
            constellation_recording.packet_number(k), ...
            constellation_recording.point_number(k), ...
            datestr(constellation_recording.receive_time_datenum(k), 'yyyy-mm-dd HH:MM:SS.FFF'), ...
            constellation_recording.i(k), constellation_recording.q(k));
    end
    fclose(fid);

    fig = figure('Visible', 'off');
    if point_count > 0
        plot(constellation_recording.i, constellation_recording.q, 'r.', 'MarkerSize', 10);
    end
    grid on;
    axis equal;
    xlim([-512,512]);
    ylim([-512,512]);
    xlabel('I');
    ylabel('Q');
    title(sprintf('Constellation (%d points)', point_count));
    saveas(fig, fullfile(output_folder, 'constellation.png'));
    close(fig);
    disp(['Constellation data saved to: ' output_folder]);
end

% --- Executes during object creation, after setting all properties.
function text_PAC_RX_CreateFcn(hObject, eventdata, handles)
% hObject    handle to text_PAC_RX (see GCBO)
% eventdata  reserved - to be defined in a future version of MATLAB
% handles    empty - handles not created until after all CreateFcns called

% Hint: edit controls usually have a white background on Windows.
%       See ISPC and COMPUTER.
if ispc && isequal(get(hObject,'BackgroundColor'), get(0,'defaultUicontrolBackgroundColor'))
    set(hObject,'BackgroundColor','white');
end

% --- Executes during object creation, after setting all properties.
function text_PAC_TX_CreateFcn(hObject, eventdata, handles)
% hObject    handle to text_PAC_RX (see GCBO)
% eventdata  reserved - to be defined in a future version of MATLAB
% handles    empty - handles not created until after all CreateFcns called

% Hint: edit controls usually have a white background on Windows.
%       See ISPC and COMPUTER.
if ispc && isequal(get(hObject,'BackgroundColor'), get(0,'defaultUicontrolBackgroundColor'))
    set(hObject,'BackgroundColor','white');
end
