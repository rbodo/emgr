function W = emgr(f,g,s,t,w,pr,nf,ut,us,xs,um,xm)
% emgr - Empirical Gramian Framework ( Version: 3.5 )
% by Christian Himpe 2013-2015 ( http://gramian.de )
% released under BSD 2-Clause License ( opensource.org/licenses/BSD-2-Clause )
%
% SYNTAX:
%    W = emgr(f,g,s,t,w,[pr],[nf],[ut],[us],[xs],[um],[xm]);
%
% SUMMARY:
%    emgr - Empirical Gramian Framemwork,
%    computation of empirical gramians for model reduction,
%    system identification and uncertainty quantification.
%    Enables gramian-based nonlinear model order reduction.
%    Compatible with OCTAVE and MATLAB.
%
% ARGUMENTS:
%   (func handle)  f - system function handle; signature: xdot = f(x,u,p)
%   (func handle)  g - output function handle; signature:    y = g(x,u,p)
%        (vector)  s - system dimensions [inputs,states,outputs]
%        (vector)  t - time discretization [start,step,stop]
%          (char)  w - gramian type:
%            * 'c' : empirical controllability gramian (WC)
%            * 'o' : empirical observability gramian (WO)
%            * 'x' : empirical cross gramian (WX)
%            * 'y' : empirical linear cross gramian (WY)
%            * 's' : empirical sensitivity gramian (WS)
%            * 'i' : empirical identifiability gramian (WI)
%            * 'j' : empirical joint gramian (WJ)
% (matrix,vector,scalar) [pr = 0] - parameters, each column is one set
%        (vector,scalar) [nf = 0] - options, 10 components:
%            + zero(0),init(1),steady(2),mean(3),median(4),midr(5),rms(6) center
%            + linear(0), log(1), geom(2), single(3), sparse(4) input scales
%            + linear(0), log(1), geom(2), single(3), sparse(4) state scales
%            + unit(0), reciproce(1), dyadic(2), single(3) input rotations
%            + unit(0), reciproce(1), dyadic(2), single(3) state rotations
%            + single(0), double(1), scaled(2) run
%            + default(0), non-symmetric cross gramian(1); only: WX, WJ
%            + default(0), robust parameters(1); only: WC, WY
%            + default(0), linear(1), exponential(2) parameter centering
%            + default(0), exclusive options:
%                  * use mean-centered(1); only: WS
%                  * use schur-complement(1); only: WI
%                  * use symmetric-part of state cross gramian(1); only: WJ
%  (matrix,vector,scalar) [ut = 1] - input; default: delta impulse
%         (vector,scalar) [us = 0] - steady-state input
%         (vector,scalar) [xs = 0] - steady-state, initial state x0
%  (matrix,vector,scalar) [um = 1] - input scales
%  (matrix,vector,scalar) [xm = 1] - initial-state scales
%
% RETURNS:
%            (matrix)  W - Gramian Matrix (only: WC, WO, WX, WY)
%              (cell)  W - {State-,Parameter-} Gramian (only: WS, WI, WJ)
%
% CITATION:
%    C. Himpe (2015). emgr - Empirical Gramian Framework (Version 3.5)
%    [Software]. Available from http://gramian.de . doi:10.5281/zenodo.31638 .
%
% SEE ALSO:
%    gram
%
% KEYWORDS:
%    model reduction, empirical gramian, cross gramian, mor
%
% Further information: <http://gramian.de>
%*

    % Custom ODE Solver
    global ODE; if(isa(ODE,'function_handle')==0), ODE = @rk2; end;

    % Version Info
    if( nargin==1 && strcmp(f,'version') ), W = 3.5; return; end;

    % Default Arguments
    if( nargin<6)  || (isempty(pr) ), pr = 0.0; end;
    if( nargin<7)  || (isempty(nf) ), nf = 0;   end;
    if( nargin<8)  || (isempty(ut) ), ut = 1.0; end;
    if( nargin<9)  || (isempty(us) ), us = 0.0; end;
    if( nargin<10) || (isempty(xs) ), xs = 0.0; end;
    if( nargin<11) || (isempty(um) ), um = 1.0; end;
    if( nargin<12) || (isempty(xm) ), xm = 1.0; end;

    % System Dimensions
    J = s(1);                 % number of inputs
    N = s(2);                 % number of states
    O = s(3);                 % number of outputs
    M = N; if(numel(s)==4), M = s(4); end; % number of non-constant states

    h = t(2);                     % width of time step
    T = round((t(3)-t(1))/h) + 1; % number of time steps plus initial value

    w = lower(w);             % ensure lower case gramian type

    P = size(pr,1);           % number of parameters
    Q = size(pr,2);           % number of parameter sets

    % Chirp Input
    if( isnumeric(ut) && numel(ut)==1 && ut==Inf )
        ut = @(t) 0.5*cos(pi./t)+0.5;
    end;

    % Discretize Procedural Input
    if(isa(ut,'function_handle'))
        uf = ut;
        ut = zeros(J,T);
        for l=1:T
            ut(:,l) = uf(l*h);
        end;
    end;

    % Lazy Arguments
    if( isnumeric(g) && g==1 ), g = @(x,u,p) x; O = N; end;

    if(numel(nf)<10), nf(10)    = 0;  end;
    if(numel(ut)==1), ut(1:J,1) = (1.0/h)*ut; end;
    if(numel(us)==1), us(1:J,1) = us; end;
    if(numel(xs)==1), xs(1:N,1) = xs; end;
    if(numel(um)==1), um(1:J,1) = um; end;
    if(numel(xm)==1), xm(1:N+(w=='y')*(J-N),1) = xm; end;

    if(size(ut,2)==1), ut(:,2:T) = 0.0; end;
    if(size(us,2)==1), us = repmat(us,[1,T]); end;
    if(size(um,2)==1), um = scales(um,nf(2),nf(4)); end;
    if(size(xm,2)==1), xm = scales(xm,nf(3),nf(5)); end;

%% PARAMETRIC SETUP

    if( (nf(8) && w~='o') || w=='s' || w=='i' || w=='j' )

        Q = 1;

        if( nf(8) || w=='s' ) % assemble (controllability) parameter scales
            if(size(pr,2)==1)
                pm = scales(pr,nf(2),nf(4));
            else
                pn = size(um,2);
                pm = max(pr,[],2)*(1:pn)./pn - min(pr,[],2)*((1:pn)./pn - 1.0);
                pr = min(pr,[],2);
            end;
        end;

        if( w=='i' || w=='j' ) % assemble (observability) parameter scales
            if(size(pr,2)==1)
                pm = scales(pr,nf(3),nf(5));
            else
                pn = size(xm,2);
                pm = max(pr,[],2)*(1:pn)./pn - min(pr,[],2)*((1:pn)./pn - 1.0);
                pr = min(pr,[],2);
            end;
        end;

        switch(nf(9)) % parameter centering

            case 1, % linear
                pr = mean(pm,2);
                pm = bsxfun(@minus,pm,pr);

            case 2, % logarithmic 
                pr = min(pm,[],2);
                ld = log(max(pm,[],2)) - log(pr);
                pm = bsxfun(@minus,pr.*exp(ld*linspace(0,1,size(pm,2))),pr);
        end;
    end;

%% STATE-SPACE SETUP

    if(w=='c' || w=='o' || w=='x' || w=='y')

        C = size(um,2); % number of input scales
        D = size(xm,2); % number of state scales

        switch(nf(1)) % residuals

            case 1, % initial state
                res = @(d) d(:,1);

            case 2, % steady state
                res = @(d) d(:,end);

            case 3, % mean state
                res = @(d) mean(d,2);

            case 4, % median state
                res = @(d) median(d,2);

            case 5, % midrange
                res = @(d) 0.5*(min(d,2)+max(d,2));

            case 6, % rms
                res = @(d) sqrt(sum(d.*d,2));

            otherwise, % zero state
                res = @(d) zeros(size(d,1),1);
        end;

        switch(nf(6)) % scaled runs

            case 1, % preconditioned run
                nf(6) = 0;
                WT = emgr(f,g,s,t,w,pr,nf,ut,us,xs,um,xm);
                TX = sqrt(diag(WT));
                TX = TX(1:M);
                tx = 1.0./TX;
                F = f; f = @(x,u,p) TX.*F(tx.*x,u,p);
                G = g; g = @(x,u,p)     G(tx.*x,u,p);

            case 2, % steady state (input) scaled run
                TU = us(:,1);
                TX = xs;
                TX = TX(1:M);
                TU(TU==0) = 1.0; tu = 1.0./TU;
                TX(TX==0) = 1.0; tx = 1.0./TX;
                F = f; f = @(x,u,p) TX.*F(tx.*x,tu.*u,p);
                G = g; g = @(x,u,p)     G(tx.*x,tu.*u,p);
        end;

        if(nf(8)) % robust parameter
            J = J + P;
            ut = [ut;ones(P,T)];
            us = [us;repmat(pr,[1,T])];
            um = [um;pm];
            if(w=='y'), xm = [xm;pm]; end;
            F = f; f = @(x,u,p) F(x,u(1:J-P),u(J-P+1:J));
            G = g; g = @(x,u,p) G(x,u(1:J-P),u(J-P+1:J));
        end;

        W = zeros(N-(M<N && w=='x')*P,N); % preallocate gramian
    end;

%% GRAMIAN COMPUTATION

    switch(w) % by empirical gramian types

        case 'c', % controllability gramian
            for q=1:Q
                pp = pr(:,q);
                for c=1:C
                    for j=1:J % parfor
                        uu = us + bsxfun(@times,ut,sparse(j,1,um(j,c),J,1));
                        x = ODE(f,1,t,xs,uu,pp);
                        x = bsxfun(@minus,x,res(x));
                        x = x * (1.0./(um(j,c) + (um(j,c)==0)));
                        W = W + (x*x'); % offload
                    end;
                end;
            end;
            W = W * (h/(C*Q));

        case 'o', % observability gramian
            o = zeros(O*T,N);
            for q=1:Q
                pp = pr(:,q);
                for d=1:D
                    for n=1:N % parfor
                        xx = xs + sparse(n,1,xm(n,d),N,1);
                        if(M<N)
                            y = ODE(f,g,t,xx(1:M),us,xx(M+1:end));
                        else
                            y = ODE(f,g,t,xx,us,pp);
                        end;
                        y = bsxfun(@minus,y,res(y));
                        y = y * (1.0/(xm(n,d) + (xm(n,d)==0)));
                        o(:,n) = reshape(y,[O*T,1]);
                    end;
                    W = W + (o'*o); % offload
                end;
            end;
            W = W * (h/(D*Q));

        case 'x', % cross gramian
            if(J~=O && nf(7)==0), error('ERROR! emgr: non-square system!'); end;
            o = zeros(O,T,N);
            for q=1:Q
                pp = pr(:,q);
                for d=1:D
                    for n=1:N % parfor
                        xx = xs + sparse(n,1,xm(n,d),N,1);
                        if(M<N)
                            y = ODE(f,g,t,xx(1:M),us,xx(M+1:end));
                        else
                            y = ODE(f,g,t,xx,us,pp);
                        end;
                        y = bsxfun(@minus,y,res(y));
                        y = y * (1.0/(xm(n,d) + (xm(n,d)==0)));
                        o(:,:,n) = y;
                    end;
                    o = permute(o,[2,3,1]); % generalized transposition
                    for c=1:C
                        for j=1:J % parfor
                            uu = us + bsxfun(@times,ut,sparse(j,1,um(j,c),J,1));
                            if(M<N)
                                x = ODE(f,1,t,xs(1:M),uu,xs(M+1:end));
                            else
                                x = ODE(f,1,t,xs,uu,pp);
                            end;
                            x = bsxfun(@minus,x,res(x));
                            x = x * (1.0./(um(j,c) + (um(j,c)==0)));
                            if(nf(7))
                                K = 1:O; % non-symmetric cross gramian
                            else
                                K = j; % regular cross gramian
                            end;
                            for k=K
                                W = W + (x*o(:,:,k)); % offload
                            end;
                        end;
                    end;
                    o = reshape(o,O,T,N); % reset
                end;
            end;
            W = W * (h/(C*D*Q));

        case 'y', % linear cross gramian
            if(J~=O && nf(8)==0), error('ERROR! emgr: non-square system!'); end;
            for q=1:Q
                pp = pr(:,q);
                for c=1:C
                    for j=1:J % parfor
                        uu = us + bsxfun(@times,ut,sparse(j,1,um(j,c),J,1));
                        x = ODE(f,1,t,xs,uu,pp);
                        x = bsxfun(@minus,x,res(x));
                        x = x * (1.0./(um(j,c) + (um(j,c)==0)));
                        uu = us + bsxfun(@times,ut,sparse(j,1,xm(j,c),J,1));
                        z = ODE(g,1,t,xs,uu,pp);
                        z = bsxfun(@minus,z,res(z));
                        z = z * (1.0./(xm(j,c) + (xm(j,c)==0)));
                        W = W + (x*z'); % offload
                    end;
                end;
            end;
            W = W * (h/(C*Q));

        case 's', % sensitivity gramian
            W = cell(1,2);
            ps = sparse(P,1);
            nf(8) = 0;
            W{1} = emgr(f,g,[J,N,O],t,'c',ps,nf,ut,us,xs,um,xm);
            W{2} = speye(P);
            F = @(x,u,p) f(x,us(:,1),pr + p*u);
            G = @(x,u,p) g(x,us(:,1),pr + p*u);
            for p=1:P
                ps = sparse(p,1,1,P,1);
                V = emgr(F,G,[1,N,O],t,'c',ps,nf,1,0,xs,pm(p,:),xm);
                W{1} = W{1} + V;      % approximate controllability gramian
                W{2}(p,p) = trace(V); % sensitivity gramian
            end;
            if(nf(10))
                W{2} = W{2} - mean(diag(W{2}));
            end;

        case 'i', % identifiability gramian
            W = cell(1,2);
            ps = sparse(P,1);
            V = emgr(f,g,[J,N+P,O,N],t,'o',ps,nf,ut,us,[xs;pr],um,[xm;pm]);
            W{1} = V(1:N,1:N);         % observability gramian
            W{2} = V(N+1:N+P,N+1:N+P); % approximate identifiability gramian
            if(nf(10))
                W{2} = W{2} - V(N+1:N+P,1:N)*ainv(W{1})*V(1:N,N+1:N+P);
            end;

        case 'j', % joint gramian
            W = cell(1,2);
            ps = sparse(P,1);
            V = emgr(f,g,[J,N+P,O,N],t,'x',ps,nf,ut,us,[xs;pr],um,[xm;pm]);
            W{1} = V(1:N,1:N); % cross gramian
            %W{2} = zeros(P);   % cross-identifiability gramian
            if(nf(10))
                W{2} = -0.5*V(1:N,N+1:N+P)'*ainv(W{1})*V(1:N,N+1:N+P);
            else
                W{2} = -0.5*V(1:N,N+1:N+P)'*ainv(W{1}+W{1}')*V(1:N,N+1:N+P);
            end

        otherwise,
            error('ERROR! emgr: unknown gramian type!');
    end;
end

%% ======== SCALES SELECTOR ========
function s = scales(s,d,e)

    switch(d)

        case 0, % linear
            s = s*[0.25,0.50,0.75,1.0];

        case 1, % logarithmic
            s = s*[0.001,0.01,0.1,1.0];

        case 2, % geometric
            s = s*[0.125,0.25,0.5,1.0];

        case 4, % sparse
            s = s*[0.17,0.5,0.77,0.94];

        otherwise, % single
            %s = s;
    end;

    switch(e)

        case 1, % reciproce
            s = [1.0./s,s];

        case 2, % dyadic
            s = s*s';

        case 3, % single
            %s = s;

        otherwise, % unit
            s = [-s,s];
    end;
end

%% ======== FAST APPROXIMATE INVERSION ========
function x = ainv(m)

    d = 1.0./diag(m);
    n = numel(d);
    x = bsxfun(@times,m,-d);
    x = bsxfun(@times,x,d');
    x(1:n+1:end) = d;
end

%% ======== DEFAULT ODE INTEGRATOR ========
function x = rk2(f,g,t,z,u,p)

    if(isnumeric(g) && g==1), g = @(x,u,p) x; end;

    h = t(2);
    L = round((t(3)-t(1))/h);

    x(:,1) = g(z,u(:,end),p);
    x(end,L+1) = 0; % preallocate trajectory

    for l=1:L % 2nd order Ralston's Runge-Kutta Method
        k1 = h*f(z,u(:,l),p);
        k2 = h*f(z + 0.666666666666667*k1,u(:,l),p);
        z = z + 0.25*k1 + 0.75*k2;
        x(:,l+1) = g(z,u(:,l),p);
    end;
end
