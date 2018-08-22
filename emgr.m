function W = emgr(f,g,s,t,w,pr,nf,ut,us,xs,um,xm,dp)
%% emgr - EMpirical GRamian Framework
%
%  project: emgr ( https://gramian.de )
%  version: 5.5 ( 2018-08-22 )
%  authors: Christian Himpe ( 0000-0003-2194-6754 )
%  license: BSD-2-Clause License ( opensource.org/licenses/BSD-2-Clause )
%  summary: Empirical Gramians for (nonlinear) input-output systems.
%
% USAGE:
%
%  W = emgr(f,g,s,t,w,[pr],[nf],[ut],[us],[xs],[um],[xm],[dp])
%
% DESCRIPTION:
%
%  Empirical gramian matrix and empirical covariance matrix computation
%  for model reduction, decentralized control, nonlinearity quantification,
%  sensitivity analysis, parameter identification, uncertainty quantification &
%  combined state and parameter reduction of large-scale input-output systems.
%  Data-driven analysis of input-output coherence and system-gramian-based
%  nonlinear model order reduction. Compatible with OCTAVE and MATLAB.
%
% ARGUMENTS:
%
%   f {handle} vector field handle: x' = f(x,u,p,t)
%   g {handle} output function handle: y = g(x,u,p,t)
%   s {vector} system dimensions: [inputs,states,outputs]
%   t {vector} time discretization: [time-step,time-horizon]
%   w {string} single character encoding gramian type:
%    * 'c' empirical controllability gramian (Wc)
%    * 'o' empirical observability gramian (Wo)
%    * 'x' empirical cross gramian (Wx aka Wco or Xcg)
%    * 'y' empirical linear cross gramian (Wy)
%    * 's' empirical sensitivity gramian (Ws)
%    * 'i' empirical identifiability gramian (Wi)
%    * 'j' empirical joint gramian (Wj)
%  pr {matrix|0} parameters, each column is one set
%  nf {vector|0} option flags, twelve components, default zero:
%    * center: no(0), steady(1), last(2), mean(3), rms(4), midrange(5)
%    * input scales: single(0), linear(1), geometric(2), log(3), sparse(4)
%    * state scales: single(0), linear(1), geometric(2), log(3), sparse(4)
%    * input rotations: unit(0), single(1)
%    * state rotations: unit(0), single(1)
%    * normalization (only: Wc, Wo, Wx, Wy): none(0), Jacobi(1), steady-state(2)
%    * cross gramian type (only: Wx, Wy, Wj): regular(0), non-symmetric(1)
%    * extra input (only: Wo, Wx, Ws, Wi, Wj): none(0), yes(1)
%    * parameter centering (only: Ws, Wi, Wj): none(0), linear(1), log(2)
%    * parameter gramian variant:
%      * Averaging type (only: Ws): input-state(0), input-output(1)
%      * Schur-complement (only: Wi, Wj): detailed(0), approximate(1)
%    * cross gramian partition size (only: Wx, Wj): full(0), partitioned(<N)
%    * cross gramian partition index (only: Wx, Wj): partition(>0)
%  ut {handle|1} input function handle: u_t = ut(t), default: delta-impulse(1)
%  us {vector|0} steady-state input
%  xs {vector|0} steady-state and initial state x_0
%  um {matrix|1} input scales
%  xm {matrix|1} initial-state scales
%  dp {handle|@mtimes} custom inner product handle: z = dp(x,y)
%
% RETURNS:
%
%  W {matrix} Gramian Matrix (for: Wc, Wo, Wx, Wy)
%  W  {cell}  [State-, Parameter-] Gramian (for: Ws, Wi, Wj)
%
% CITATION:
%
%  C. Himpe (2018). emgr - EMpirical GRamian Framework (Version 5.5)
%  [Software]. Available from https://gramian.de . doi:10.5281/zenodo.1401500
%
% SEE ALSO:
%
%  gram
%
% KEYWORDS:
%
%  model reduction, system gramians, empirical gramians, cross gramian, MOR
%
% Further information: https://gramian.de

    % Integrator Handle
    global ODE;
    if(not(isa(ODE,'function_handle'))), ODE = @ssp2; end

    % Version Info
    if(strcmp(f,'version')), W = 5.5; return; end

    % Default Arguments
    if( (nargin<6)  || isempty(pr) ), pr = 0.0; end
    if( (nargin<7)  || isempty(nf) ), nf = 0.0; end
    if( (nargin<8)  || isempty(ut) ), ut = 1.0; end
    if( (nargin<9)  || isempty(us) ), us = 0.0; end
    if( (nargin<10) || isempty(xs) ), xs = 0.0; end
    if( (nargin<11) || isempty(um) ), um = 1.0; end
    if( (nargin<12) || isempty(xm) ), xm = 1.0; end
    if( (nargin<13) || isempty(dp) ), dp = @mtimes; end

%% GENERAL SETUP

    % System Dimensions
    M = s(1);                   % Number of inputs
    N = s(2);                   % Number of states
    Q = s(3);                   % Number of outputs
    A = (numel(s)==4) * s(end); % Number of augmented parameter-states
    P = size(pr,1);             % Dimension of parameter
    K = size(pr,2);             % Number of parameter-sets
    h = t(1);                   % Time-step width
    L = floor(t(2)/h) + 1;      % Number of time-steps plus initial value

    % Lazy Output Functional
    if(isnumeric(g) && g==1)
        g = @id;
        Q = N;
    end

    % Ensure lower case gramian type
    w = lower(w);

    % Ensure flag vector length
    if(numel(nf)<12), nf(12) = 0; end

    % Built-in input functions
    if(isnumeric(ut) && isscalar(ut))
        switch(ut)

            case 0 % Pseudorandom Binary Input
                ut = @(t) randi([0,1],M,1);

            case Inf % Exponential Chirp Input
                mh = 0.5 * ones(M,1);
                gr = (10.0/L)^(1.0/(L*h));
                st = (2.0*pi) * (0.1/h) / log(gr);
                ut = @(t) mh * cos(st * (gr.^t-1.0)) + 0.5;

            otherwise % Delta Impulse Input
                mh = ones(M,1)./h;
                ut = @(t) mh * (t<=h);
        end
    end

    % Lazy Optional Arguments
    if(isscalar(us)), us = us * ones(M,1); end
    if(isscalar(xs)), xs = xs * ones(N,1); end
    if(isscalar(um)), um = um * ones(M,1); end
    if(isscalar(xm)), xm = xm * ones(N-((w=='y')*(N-M)),1); end

    if(size(um,2)==1), um = scales(um,nf(2),nf(4)); end
    if(size(xm,2)==1), xm = scales(xm,nf(3-(w=='y')),nf(5-(w=='y'))); end

    C = size(um,2); % Number of input scales sets
    D = size(xm,2); % Number of state scales sets

%% GRAMIAN SETUP

    % Gramian Normalization
    if( (w=='c' || w=='o' || w=='x' || w=='y') && nf(6) && A==0)

        TX = ones(N,1);
        switch(nf(6))

            case 1 % Jacobi-type preconditioner
                NF = nf; NF(6) = 0;
                DP = @(x,y) sum(x.*y',2); % Diagonal-only pseudo-kernel
                WT = emgr(f,g,s,t,w,pr,NF,ut,us,xs,um,xm,DP);
                TX = sqrt(abs(WT));

            case 2 % Steady-state preconditioner
                TX(xs~=0) = xs(xs~=0);
        end
        tx = 1.0./TX;
        F = f; f = @(x,u,p,t) tx.*F(TX.*x,u,p,t);
        G = g; g = @(x,u,p,t)     G(TX.*x,u,p,t);
        xs = tx.*xs;
    end

    % Extra input
    if( (w=='o' || w=='x' || w=='s') && nf(8) )
        up = @(t) us + ut(t);
    else
        up = @(t) us;
    end

%% GRAMIAN COMPUTATION

    switch(w) % Empirical gramian types

        % General layout:
        %   Parameter gramians call state gramians
        %   Initialize empirical gramian variable
        %   For each {parameter, scale, input/state/parameter}:
        %     Perturb, simulate, center, normalize, accumulate
        %   Assemble, normalize, post-process

        case 'c' % Controllability Gramian

            W = 0; % Reserve gramian variable
            for k = 1:K
                for c = 1:C
                    for m = find(um(:,c))' % parfor
                        em = sparse(m,1,um(m,c),M,1);
                        uu = @(t) us + ut(t) .* em;
                        x = ODE(f,@id,t,xs,uu,pr(:,k));
                        x = x - avg(x,nf(1),xs,t);
                        x = x * (1.0/um(m,c));
                        if(A>0)
                            W = W + ((1:M)==m)' * dp(x,x');
                        else
                            W = W + dp(x,x');
                        end;
                    end;
                end;
            end;
            W = W * (h/(C*K));

        case 'o' % Observability gramian

            W = 0; % Reserve gramian variable
            o = zeros(Q*L,N+A); % Pre-allocate observability matrix
            for k = 1:K
                for d = 1:D
                    for n = find(xm(:,d))' % parfor
                        xx = xs + sparse(n,1,xm(n,d),N+A,1);
                        if(A>0), pk = xx(N+1:end); else, pk = pr(:,k); end;
                        y = ODE(f,g,t,xx(1:N),up,pk);
                        y = y - avg(y,nf(1),g(xs(1:N),us,pk,0),t);
                        y = y * (1.0/xm(n,d));
                        o(:,n) = y(:);
                    end;
                    W = W + dp(o',o);
                end;
            end;
            W = W * (h/(D*K));

        case 'x' % Cross gramian

            assert(M==Q || nf(7),'emgr: non-square system!');

            i0 = 1;
            i1 = N+A;

            % Partitioned cross gramian
            if(nf(11)>0)
                np = round(nf(11));      % Partition size
                ip = round(nf(12));      % Partition index
                i0 = i0 + (ip - 1) * np; % Start index
                i1 = min(i0 + np - 1,N); % End index
                if(i0>N),
                    i0 = i0 - (ceil( N / np ) * np - N);
                    i1 = min(i0 + np - 1,N+A);
                end

                if(ip<1 || i0>i1 || i0<0), W = 0; return; end
            end

            W = 0; % Reserve gramian (partition) variable
            o = zeros(L,i1-i0+1,Q); % Pre-allocate observability 3-tensor
            for k = 1:K
                for d = 1:D
                    for n = find(xm(i0:i1,d))' % parfor
                        xx = xs + sparse(i0-1+n,1,xm(i0-1+n,d),N+A,1);
                        if(A>0), pk = xx(N+1:end); else, pk = pr(:,k); end;
                        y = ODE(f,g,t,xx(1:N),up,pk);
                        y = y - avg(y,nf(1),g(xs(1:N),us,pk,0),t);
                        y = y * (1.0/xm(i0-1+n,d));
                        o(:,n,:) = y';
                    end;
                    if(nf(7)) % Non-symmetric cross gramian: cache average
                        o(:,:,1) = sum(o,3);
                    end;
                    for c = 1:C % parfor
                        for m = find(um(:,c))'
                            em = sparse(m,1,um(m,c),M,1);
                            uu = @(t) us + ut(t) .* em;
                            if(A>0), pk = xs(N+1:end); else, pk = pr(:,k); end;
                            x = ODE(f,@id,t,xs(1:N),uu,pk);
                            x = x - avg(x,nf(1),xs(1:N),t);
                            x = x * (1.0/um(m,c));
                            if(nf(7)) % Non-symmetric cross gramian
                                W = W + dp(x,o(:,:,1));
                            else      % Regular cross gramian
                                W = W + dp(x,o(:,:,m));
                            end;
                        end;
                    end;
                end;
            end;
            W = W * (h/(C*D*K));

        case 'y' % Linear cross gramian

            assert(M==Q || nf(7),'emgr: non-square system!');
            assert(C==D,'emgr: scale count mismatch!');

            W = 0; % Reserve gramian variable
            a = zeros(L,N,M); % Pre-allocate adjoint 3-tensor
            for k = 1:K
                for c = 1:C
                    for m = find(xm(:,c))' % parfor
                        em = sparse(m,1,xm(m,c),Q,1);
                        uu = @(t) us + ut(t) .* em;
                        z = ODE(g,@id,t,xs,uu,pr(:,k));
                        z = z - avg(z,nf(1),xs,t);
                        z = z * (1.0/xm(m,c));
                        a(:,:,m) = z';
                    end;
                    if(nf(7)) % Non-symmetric cross gramian: cache average
                        a(:,:,1) = sum(a,3);
                    end;
                    for m = find(um(:,c))' % parfor
                        em = sparse(m,1,um(m,c),M,1);
                        uu = @(t) us + ut(t) .* em;
                        x = ODE(f,@id,t,xs,uu,pr(:,k));
                        x = x - avg(x,nf(1),xs,t);
                        x = x * (1.0/um(m,c));
                        if(nf(7)) % Non-symmetric cross gramian
                            W = W + dp(x,a(:,:,1));
                        else      % Regular cross gramian
                            W = W + dp(x,a(:,:,m));
                        end;
                    end;
                end;
            end;
            W = W * (h/(C*K));

        case 's' % Sensitivity gramian

            [pr,pm] = pscales(pr,nf(9),C);
            W{1} = emgr(f,g,[M,N,Q],t,'c',pr,nf,ut,us,xs,um,xm,dp);
            if(not(nf(10))) % Input-state sensitivty gramian
                DP = @(x,y) sum(sum(x.*y'));     % Trace pseudo-kernel
            else            % Input-output sensitivity gramian
                av = kron(speye(L),ones(1,Q));
                DP = @(x,y) av*y;                % Custom pseudo-kernel
                V = emgr(f,g,[M,N,Q],t,'o',pr,nf,ut,us,xs,um,xm,DP)';
                DP = @(x,y) abs(sum(sum(x.*V))); % Custom pseudo-kernel
            end
            F = @(x,u,p,t) f(x,up(t),u,t);
            W{2} = emgr(F,g,[P,N,Q,P],t,'c',0,nf,@(t) 1.0,pr,xs,pm,xm,DP);
            W{2} = W{2}./max(W{2});

        case 'i' % Identifiability gramian

            [pr,pm] = pscales(pr,nf(9),D);
            V = emgr(f,g,[M,N,Q,P],t,'o',0,nf,ut,us,[xs;pr],um,[xm;pm],dp);
            W{1} = V(1:N,1:N);         % Observability gramian
            WM = V(1:N,N+1:N+P);
            W{2} = V(N+1:N+P,N+1:N+P); % Identifiability gramian
            if(not(nf(10)))
                W{2} = W{2} - (WM' * ainv(W{1}) * WM);
            end

        case 'j' % Joint gramian

            [pr,pm] = pscales(pr,nf(9),D);
            V = emgr(f,g,[M,N,Q,P],t,'x',0,nf,ut,us,[xs;pr],um,[xm;pm],dp);
            if(nf(11)), W = V; return; end; % Joint gramian partition
            W{1} = V(1:N,1:N);              % Cross gramian
            WM = V(1:N,N+1:N+P);
            if(not(nf(10)))                 % Cross-identifiability gramian
                W{2} = -0.5 * (WM' * ainv(W{1} + W{1}') * WM);
            else
                W{2} = -0.5 * (WM' * WM);
            end

        otherwise

            error('emgr: unknown gramian type!');
    end
end

%% LOCALFUNCTION: scales
function sm = scales(s,d,c)
%  summary: Input and initial state perturbation scales

    switch(d)

        case 1 % Linear
            sc = [0.25,0.50,0.75,1.0];

        case 2 % Geometric
            sc = [0.125,0.25,0.5,1.0];

        case 3 % Logarithmic
            sc = [0.001,0.01,0.1,1.0];

        case 4 % Sparse
            sc = [0.01,0.50,0.99,1.0];

        otherwise % One
            sc = 1.0;
    end

    if(c==0), sc = [-sc,sc]; end

    sm = s * sc;
end

%% LOCALFUNCTION: pscales
function [pr,pm] = pscales(p,d,c)
%  summary: Parameter perturbation scales

    assert(size(p,2)>=2,'emgr: min & max parameter required!');

    pmin = min(p,[],2);
    pmax = max(p,[],2);

    switch(d)

        case(0) % No centering and linear scales
            pr = pmin;
            pm = (pmax - pmin) * linspace(1.0/c,1.0,c);

        case(1) % Linear centering and scales
            pr = 0.5 * (pmax + pmin);
            pm = (pmax - pmin) * linspace(0,1.0,c) + (pmin - pr);

        case(2) % Logarithmic centering and scales
            lmin = log(pmin);
            lmax = log(pmax);
            pr = real(exp(0.5 * (lmax + lmin)));
            pm = real(exp((lmax - lmin) * linspace(0,1.0,c) + lmin)) - pr;
    end
end

%% LOCALFUNCTION: id
function x = id(x,u,p,t)
%  summary: Output identity function

end

%% LOCALFUNCTION: avg
function mn = avg(x,d,c,t)
%  summary: State and output trajectory centering

    switch(d)

        case 1 % Steady state / output
            mn = c;

        case 2 % Final state / output
            mn = x(:,end);

        case 3 % Temporal mean state / output
            mn = sum(abs(x),2) * (t(1)./t(2));

        case 4 % Temporal root-mean-square state / output
            mn = sqrt(sum(x.*x,2) * (t(1)./t(2)));

        case 5 % Midrange state / output
            mn = (max(x,[],2) - min(x,[],2)) * (0.5*t(2));

        otherwise % None
            mn = zeros(size(x,1),1);
    end
end

%% LOCALFUNCTION: ainv
function x = ainv(m)
%  summary: Quadratic complexity approximate inverse matrix

    d = diag(m);
    k = find(abs(d)>sqrt(eps));
    d(k) = 1.0./d(k);
    x = m .* (-d);
    x = x .* (d');
    x(1:numel(d)+1:end) = d;
end

%% LOCALFUNCTION: ssp2
function y = ssp2(f,g,t,x0,u,p)
%  summary: Low-Storage Strong-Stability-Preserving Second-Order Runge-Kutta

    global STAGES; % Configurable number of stages for increased stability

    if(not(isscalar(STAGES))), STAGES = 3; end

    h = t(1);
    K = floor(t(2)/h) + 1;

    y = g(x0,u(0),p,0);
    y(end,K) = 0; % Pre-allocate trajectory

    hs = h / (STAGES-1);
    xk1 = x0;
    xk2 = x0;

    for k = 2:K
        tk = (k - 1.5) * h;
        uk = u(tk);
        for s = 1:(STAGES-1)
            xk1 = xk1 + hs * f(xk1,uk,p,tk);
        end;
        xk1 = (xk2 + (STAGES-1) * xk1 + h * f(xk1,uk,p,tk)) ./ STAGES;
        xk2 = xk1;
        y(:,k) = g(xk1,uk,p,tk);
    end;
end
