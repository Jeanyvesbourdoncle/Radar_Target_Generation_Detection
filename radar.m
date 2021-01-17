clear all; close all;
clc;

%% Radar System Requirements

maxR = 200;           % maximum range
rangeRes = 1;         % range resolution
maxV = 70;            % maximum velocity
fc= 77e9;             %frequency operation of the radar

% other paramater :speed of the light
c = 3e8;

%% User Defined Range and Velocity of target
% define the target's initial position and velocity. Note : Velocity
% remains contant
r0 = 90; % initial position of the target (max : 200m)
v0 = 10; % velocity of the target (min =-70m/s, max=70m/s)

%% FMCW Waveform Generation
%Design the FMCW waveform by giving the specs of each of its parameters.
% Calculate the Bandwidth (B), Chirp Time (Tchirp) and Slope (slope) of the FMCW
% chirp using the requirements above.
B = c / (2*rangeRes); % Bandwith (y-axis)  
Tchirp = 5.5 * 2 * maxR/c; % Chirp Time (x-axis), 5.5= sweep time should be at least 5 o 6 times the round trip time
slope = B / Tchirp; %slope of the chirp signal


                                                          
%The number of chirps in one sequence. Its ideal to have 2^ value for the ease of running the FFT
%for Doppler Estimation. 
Nd=128;                   % #of doppler cells OR #of sent periods % number of chirps

%The number of samples on each chirp. 
Nr=1024;                  %for length of time OR # of range cells

% Timestamp for running the displacement scenario for every sample on each
% chirp
t=linspace(0,Nd*Tchirp,Nr*Nd); %total time for samples

%Creating the vectors for Tx, Rx and Mix based on the total samples input.
Tx=zeros(1,length(t)); %transmitted signal
Rx=zeros(1,length(t)); %received signal
Mix = zeros(1,length(t)); %beat signal

%Similar vectors for range_covered and time delay.
r_t=zeros(1,length(t));
td=zeros(1,length(t));

%% Signal generation and Moving Target simulation
% Running the radar scenario over the time. 
for i=1:length(t)
    
    %For each time stamp update the Range of the Target for constant velocity.
    r_t(i) = r0 + v0*t(i); % update the range
    td(i) = 2*r_t(i)/c; % delay time
    
   
    %For each time sample we need update the transmitted and
    %received signal. 
    Tx(i) = cos(2*pi*(fc*t(i) + (slope*t(i)^2)/2)); % transmitted signal
    Rx(i) = cos(2*pi*(fc*(t(i)-td(i)) + (slope*(t(i)-td(i))^2)/2)); %received signal
    
    
    %Now by mixing the Transmit and Receive generate the beat signal
    %This is done by element wise matrix multiplication of Transmit and
    %Receiver Signal
    Mix(i) = Tx(i).*Rx(i);% beat signal
end

%% RANGE MEASUREMENT

%reshape the vector into Nr*Nd array. Nr and Nd here would also define the size of
%Range and Doppler FFT respectively.
signal = reshape(Mix,Nr,Nd);

 
%run the FFT on the beat signal along the range bins dimension (Nr) and
%normalize.
sig_fft = fft(signal,Nr)./Nr;


% Take the absolute value of FFT output
sig_fft = abs(sig_fft);


% Output of FFT is double sided signal, but we are interested in only one side of the spectrum.
% Hence we throw out half of the samples.
sig_fft = sig_fft(1:(Nr/2));

%plotting the range
figure ('Name','Range from First FFT')
subplot(2,1,1)


% plot FFT output
plot(sig_fft, 'LineWidth', 2);
xlabel('Range(Frequency)');
grid on;
axis ([0 200 0 1]);
%% RANGE DOPPLER RESPONSE
% The 2D FFT implementation is already provided here. This will run a 2DFFT
% on the mixed signal (beat signal) output and generate a range doppler
% map.You will implement CFAR on the generated RDM


% Range Doppler Map Generation.

% The output of the 2D FFT is an image that has reponse in the range and
% doppler FFT bins. So, it is important to convert the axis from bin sizes
% to range and doppler based on their Max values.

Mix=reshape(Mix,[Nr,Nd]);

% 2D FFT using the FFT size for both dimensions.
sig_fft2 = fft2(Mix,Nr,Nd);

% Taking just one side of signal from Range dimension.
sig_fft2 = sig_fft2(1:Nr/2,1:Nd);
sig_fft2 = fftshift (sig_fft2);
RDM = abs(sig_fft2);
RDM = 10*log10(RDM) ;

%use the surf function to plot the output of 2DFFT and to show axis in both
%dimensions
doppler_axis = linspace(-100,100,Nd);
range_axis = linspace(-200,200,Nr/2)*((Nr/2)/400);
figure,surf(doppler_axis,range_axis,RDM);
xlabel('doppler'); ylabel('range'); zlabel('RDM');
title('Range Doppler Map');

%% CFAR implementation

%Slide Window through the complete Range Doppler Map

%Select the number of Training Cells in both the dimensions.
Tr = 8;
Td = 4;

%Select the number of Guard Cells in both dimensions around the Cell under 
%test (CUT) for accurate estimation
Gr = 4;
Gd = 2;

% offset the threshold by SNR value in dB
snr_offset = -10*log10(0.25);

%Create a vector to store noise_level for each iteration on training cells
r_margin = 2*(Tr+Gr);
d_margin = 2*(Td+Gd);
r_grid_length = Nr/2-d_margin;
d_grid_length = Nd-r_margin;
noise_level = zeros(r_grid_length,d_grid_length);

%design a loop such that it slides the CUT across range doppler map by
%giving margins at the edges for Training and Guard Cells.
%For every iteration sum the signal level within all the training
%cells. To sum convert the value from logarithmic to linear using db2pow
%function. Average the summed values for all of the training
%cells used. After averaging convert it back to logarithimic using pow2db.
%Further add the offset to it to determine the threshold. Next, compare the
%signal under CUT with this threshold. If the CUT level > threshold assign
%it a value of 1, else equate it to 0.

gridSize = (2*Tr+2*Gr+1)*(2*Td+2*Gd+1);
numGcells = (2*Gr+1)*(2*Gd+1);
numTcells = gridSize - numGcells;

% The process above will generate a thresholded block, which is smaller 
%than the Range Doppler Map as the CUT cannot be located at the edges of
%matrix. Hence,few cells will not be thresholded. To keep the map size same
% set those values to 0. 
sig_CFAR = zeros(size(RDM));

for i = 1:r_grid_length  % over range
    for j = 1:d_grid_length % over doppler
        % convert value from log to linear using db2pow
        sig_pow = db2pow(RDM(i:i+d_margin,j:j+r_margin));
        % sum signal within all training cells
        sig_sum = sum(sum(sig_pow));
        % average
        noise_level(i,j) = pow2db(sig_sum/numTcells);
        % add offset
        sig_threshold = noise_level(i,j) + snr_offset;
        
        % compare CUT to threshold
        if (RDM(i+d_margin/2, j+r_margin/2) > sig_threshold)
            sig_CFAR(i+d_margin/2, j+r_margin/2) = 1;
        end  
    end
end

%display the CFAR output using the Surf function like we did for Range
figure,surf(doppler_axis,range_axis,sig_CFAR);
colorbar;
xlabel('doppler'); ylabel('range');
title('CFAR output');