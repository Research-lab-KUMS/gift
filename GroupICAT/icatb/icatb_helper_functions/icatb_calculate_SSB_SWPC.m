function [SSBSWPC,win_idx] = icatb_calculate_SSB_SWPC(Tc,winsize,Tr,mod_fs,varargin)
    % CALCULATE_SSB_SWPC calculates single sideband modulation (SSB) + sliding
    % window Pearson correlation (SWPC)
    %  
    % Inputs:
    % 1. Tc        - The signal (Time by Component)
    % 2. winsize   - window size for the SWPC part of the algorithm should be odd
    % valued
    % 3. Tr        - sampling rate of the time series (i.e., Tr in fMRI)
    % 4. mod_fs    - modulation frequency of SSB part. It should be a positive
    % value. Assume Tc has a spectrum bounded between [a, b] Hz and the
    % cutoff of the high pass portion of SWPC is c. Therefore, the modulation
    % frequency should be between (c-a) and 1/Tr/2. If the Tc is not
    % bandlimited, one can easily make it bandlimited by up-sampling it.
    % 5. varargin  - up to 2 inputs
    %       a. win_type   - Window type for SWPC calculation (default is
    %                       'rect'). Other options are 'gauss' and 'tukey'
    %       b. plot_flag  - flag for plotting. This plots the fft of Tc and its
    %                       modulation, in addition to the transfer function of
    %                       the high pass filter portion of the sliding window
    %                       Pearson correlation (SWPC)
    %  
    % Outputs:
    % 1. SSB_SWPC_vec - estimated time-resolved connectivity
    % 2. win_center_idx - index of window center (makes sense only if winsize
    % is odd
    %  
    % Examples: 
    %   Here 10 time series are generated by drawing samples from a normal
    %   distribution. As the signals are white (i.e., not bandlimited), we have
    %   upsampled the data. We want to select a modulation frequency that shifts
    %   the spectrum out of the cutoff of the HPF (the filled area if plot_flag
    %   is 1).
    %  
    %   Tc = randn(1000,10);
    %   Tc = resample(Tc,2,1);
    %   winsize = 15;
    %   Tr = 1;
    %   mod_fs = .1;
    %   plot_flag = 1;
    %   calculate_SSB_SWPC(Tc,winsize,Tr,mod_fs,'rect',plot_flag);
    %  
    % References:
    %   [1] <my own paper> 
    %   [2] Pozzi, F., Di Matteo, T., and Aste, T.: 
    %   'Exponential smoothing weighted correlations', The European Physical 
    %   Journal B, 2012, 85, pp. 1-21
    % 
    
    
    win_type = 'rect';
    plot_flag = 0;
    if length(varargin)==1
        win_type = varargin{1};
    elseif length(varargin)==2
        win_type = varargin{1};
        plot_flag = varargin{2};
        if ~isnumeric(plot_flag)
            error('plot_flag should be 0 or 1.')
        end
    elseif length(varargin)>2
        error('maximum number of input is 6')
    end
    
    % window size should be odd. This way the center of the window will be an
    % integer
    if rem(winsize,2)==0
        warning('window size is even.')
    end
    
    switch win_type
        case 'rect'
            window_tc = rectwin(winsize);
        case 'gauss'
            window_tc = gausswin(winsize);
        case 'tukey'
            window_tc = tukeywin(winsize,.5);
        otherwise
            warning('Unexpected plot type. No plot created.')
    end
    window_tc = window_tc ./ sum(window_tc);
    Fs = 1/Tr;
    
    if mod_fs<0 | mod_fs > Fs/2
    end
    tt = 0:Tr:(size(Tc,1)-1)*Tr;
    modulation_tc = exp(1i*2*pi*mod_fs*tt);
    % note that .' is the nonconjugate transpose
    modulation_tc_mat = (modulation_tc.')*ones(1,size(Tc,2));
    Tc_a = hilbert(Tc);
    Tc_am = real(Tc_a .* modulation_tc_mat);
    
    window_num = size(Tc,1)-winsize+1;
    SSB_SWPC_mat = zeros(window_num, size(Tc_am,2),size(Tc_am,2));
    win_idx = zeros(window_num, 1);
    for w_start=1:window_num
        widx = w_start:w_start+winsize-1;
        Tc_am_windowed = Tc_am(widx,:);
        [dt, N] = size(Tc_am_windowed);
        temp = Tc_am_windowed - repmat(window_tc.' * Tc_am_windowed, dt, 1);    
        temp = temp.' * (temp .* repmat(window_tc, 1, N));
        temp = 0.5 * (temp + temp.');    
        R = diag(temp);
        SSB_SWPC_mat(w_start,:,:) = temp ./ sqrt(R * R.');
        win_idx(w_start,1) = median(widx);
    end
    [SSBSWPC, ~] = mat2vec(SSB_SWPC_mat);
    
    if plot_flag==1
        fft_n = 2^8+1;
        Tc_fft = fftshift(fft(Tc, fft_n));
        Tc_am_fft = fftshift(fft(Tc_am, fft_n));
        
        delta_tc = zeros(size(window_tc));
        delta_tc((winsize+1)/2,1)=1;
        HPF_window_fft = fftshift(fft(delta_tc - window_tc, fft_n));
        
        fft_ff = linspace(-Fs/2,Fs/2,fft_n);
        fft_ff_nonneg = fft_ff(fft_ff >= 0);
        clf
        hold on
        tmp_fft = mean(abs(Tc_fft),2);
        tmp_fft = tmp_fft./max(tmp_fft);
        tmp_fft = tmp_fft(fft_ff >= 0);
        plot(fft_ff_nonneg, tmp_fft,'LineWidth',2)
        
        tmp_fft = mean(abs(Tc_am_fft),2);
        tmp_fft = tmp_fft./max(tmp_fft);
        tmp_fft = tmp_fft(fft_ff >= 0);
        plot(fft_ff_nonneg, tmp_fft,'LineWidth',2)
    
        tmp_fft = abs(HPF_window_fft);
        tmp_fft = tmp_fft./max(tmp_fft);
        tmp_fft = tmp_fft(fft_ff >= 0);
        plot(fft_ff_nonneg, tmp_fft,'--k','LineWidth',2)
        
        % calculate and draw the cutoff frequency of the HPF. for rectangular
        % window, the cutoff can be calculated mathematically quite easily. The
        % cutoff frequency is 0.88/(sqrt(N^2-1))*Fs
        if strcmp(win_type, 'rect')
            cutoff_freq = 0.88/sqrt((winsize^2-1))*Fs;
    %         plot([cutoff_freq, cutoff_freq], [0, db2mag(-3)],'--k','LineWidth',2)
    %         plot([0, cutoff_freq], [db2mag(-3), db2mag(-3)],'--k','LineWidth',2)
            
            area([0, cutoff_freq],[db2mag(-3), db2mag(-3)],'FaceColor','k', 'FaceAlpha',.5)
        else
            cutoff_idx = [];
            dist_thr = 1e-5;
            while isempty(cutoff_idx)
                cutoff_idx = abs(tmp_fft - db2mag(-3)) < dist_thr;
                cutoff_idx = find(cutoff_idx);
                dist_thr = dist_thr + 1e-5;
            end
            cutoff_idx = cutoff_idx(1);        
            tmp_fft = abs(HPF_window_fft);
            tmp_fft = tmp_fft./max(tmp_fft);
            tmp_fft = tmp_fft(fft_ff>=0);
    %         plot([fft_ff_nonneg(cutoff_idx), fft_ff_nonneg(cutoff_idx)], [0, db2mag(-3)],'--k','LineWidth',2)
    %         plot([0, fft_ff_nonneg(cutoff_idx)], [db2mag(-3), db2mag(-3)],'--k','LineWidth',2)
            area([0, fft_ff_nonneg(cutoff_idx)],[db2mag(-3), db2mag(-3)],'FaceColor','k', 'FaceAlpha',.5)
        end
        
        hold off
        xlabel('Freq (Hz)')
        ylabel('Normalized amplitude')
        yticks([0 db2mag(-3) 1])
        yticklabels({'0', '-3db', '1'})
        grid on
        ylim([0 1.4])
        xlim([0, Fs/2])
        lgd = legend({'Tc','modulated Tc','HPF transfer function','HPF cutoff'});
        lgd.FontSize = 12;
    end
    end
    
    
    function [vec, IND] = mat2vec(mat)
    % [vec, IND] = mat2vec(mat)
    % Returns the lower triangle of mat
    % mat should be square [m x m], or if 3-dims should be [n x m x m]
    
    if ndims(mat) == 2    
        [n,m] = size(mat);
        if n ~=m
            error('mat must be square!')
        end
    elseif ndims(mat) == 3    
        [n,m,m2] = size(mat);
        if m ~= m2
            error('2nd and 3rd dimensions must be equal!')
        end
    end
    
    temp = ones(m);
    %% find the indices of the lower triangle of the matrix
    IND = find((temp-triu(temp))>0);
    if ndims(mat) == 2
        vec = mat(IND);
    else
        mat = reshape(mat, n, m*m2);
        vec = mat(:,IND);
    end
    
    end
    