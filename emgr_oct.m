function W = emgr_oct(f,g,s,t,w,pr=0.0,nf=0,ut=1.0,us=0.0,xs=0.0,um=1.0,xm=1.0,yd=0)
# emgr - Empirical Gramian Framework ( Version: 3.0.oct )
# by Christian Himpe 2013-2015 ( http://gramian.de )
# released under BSD 2-Clause License ( opensource.org/licenses/BSD-2-Clause )
#
# SYNTAX:
#    W = emgr(f,g,s,t,w,[pr],[nf],[ut],[us],[xs],[um],[xm],[yd]);
#
# ABOUT:
#    emgr - Empirical Gramian Framemwork,
#    computation of empirical gramians for model reduction,
#    system identification and uncertainty quantification.
#    Enables gramian-based nonlinear model order reduction.
#    Compatible with OCTAVE and MATLAB.
#
# ARGUMENTS:
#   (func handle)  f - system function handle; signature: xdot = f(x,u,p)
#   (func handle)  g - output function handle; signature:    y = g(x,u,p)
#        (vector)  s - system dimensions [inputs,states,outputs]
#        (vector)  t - time discretization [start,step,stop]
#          (char)  w - gramian type:
#            * 'c' : empirical controllability gramian (WC)
#            * 'o' : empirical observability gramian (WO)
#            * 'x' : empirical cross gramian (WX)
#            * 'y' : empirical linear cross gramian (WY)
#            * 's' : empirical sensitivity gramian (WS)
#            * 'i' : empirical identifiability gramian (WI)
#            * 'j' : empirical joint gramian (WJ)
# (matrix,vector,scalar) [pr = 0] - parameters, each column is one set
#        (vector,scalar) [nf = 0] - options, 12 components:
#            + zero(0), mean(1), median(2), steady(3), pod(4), pca(5) centering
#            + linear(0), log(1), geometric(2), single(3) input scale spacing
#            + linear(0), log(1), geometric(2), single(3) state scale spacing
#            + unit(0), reciproce(1), dyadic(2), single(3) input rotations
#            + unit(0), reciproce(1), dyadic(2), single(3) state rotations
#            + single(0), double(1), scaled(2) run
#            + default(0), data-driven gramians(1)
#            + default(0), robust parameters(1); only: WC,WY
#            + default(0), parameter centering(1); only: WC,WX,WY,WS,WI,WJ
#            + default(0), exclusive options:
#                  * use mean-centered(1); only: WS
#                  * use schur-complement(1); only: WI
#                  * non-symmetric cross gramian(1); only: WX,WJ
#            + default(0), enforce gramian symmetry(1); only: WC,WO,WX,WY
#            + Improved Runge-Kutta-3(0), Custom solver handle(-1)
#  (matrix,vector,scalar) [ut = 1] - input; default: delta impulse
#         (vector,scalar) [us = 0] - steady-state input
#         (vector,scalar) [xs = 0] - steady-state, initial state x0
#  (matrix,vector,scalar) [um = 1] - input scales
#  (matrix,vector,scalar) [xm = 1] - initial-state scales
#           (cell,matrix) [yd = 0] - observed data
#
# RETURNS:
#            (matrix)  W - Gramian Matrix (WC, WO, WX, WY only)
#              (cell)  W - {State-,Parameter-} Gramian (WS, WI, WJ only)
#
# CITATION:
#    C. Himpe (2015). emgr - Empirical Gramian Framework (Version 3.0)
#    [Computer Software]. Available from http://gramian.de
#
# SEE ALSO:
#    gram
#
# KEYWORDS:
#    model reduction, empirical gramian, cross gramian, mor
#
# Further information: <http://gramian.de>
#*

    # Version Info
    if(nargin==1 && strcmp(f,'version')), W = 3.0; return; end;

    # System Constants:
    J = s(1);                 # number of inputs
    N = s(2);                 # number of states
    O = s(3);                 # number of outputs
    h = t(2);                 # width of time step
    T = round((t(3)-t(1))/h); # number of time steps
    P = size(pr,1);           # number of parameters
    Q = size(pr,2);           # number of parameter sets

    if(isnumeric(g) && g==1), g = @(x,u,p) x; O = N; end; # lazy output

    w = lower(w);

    if(ut==Inf) # chirp input
        ut = @(t) 0.5*cos(pi./t)+0.5;
    end;

    if(isa(ut,'function_handle')) # procedural input
        uf = ut;
        ut = zeros(J,T);
        for l=1:T, ut(:,l) = uf(l*h); end;
    end;

    # Lazy Arguments:
    if(numel(nf)<13), nf(13)    = 0;  end;
    if(numel(ut)==1), ut(1:J,1) = (2.0/h)*ut; end;
    if(numel(us)==1), us(1:J,1) = us; end;
    if(numel(xs)==1), xs(1:N,1) = xs; end;
    if(numel(um)==1), um(1:J,1) = um; end;
    if(numel(xm)==1), xm(1:N+(w=='y')*(J-N),1) = xm; end;

    if(size(ut,2)==1), ut(:,2:T) = 0.0; end;
    if(size(us,2)==1), us = repmat(us,[1,T]); end;
    if(size(um,2)==1), um = scales(um,nf(2),nf(4)); end;
    if(size(xm,2)==1), xm = scales(xm,nf(3),nf(5)); end;

## PARAMETRIC SETUP

    if( (nf(8) && w~='o') || w=='s' || w=='i' || w=='j')

        Q = 1;

        if(nf(8) || w=='s') # assemble (controllability) parameter scales
            if(size(pr,2)==1)
                pm = scales(pr,nf(2),nf(4));
            else
                pn = size(um,2);
                pm = max(pr,[],2)*(1:pn)./pn - min(pr,[],2)*((1:pn)./pn - 1.0);
                pr = min(pr,[],2);
            end;
        end;

        if(w=='i' || w=='j') # assemble (observability) parameter scales
            if(size(pr,2)==1)
                pm = scales(pr,nf(3),nf(5));
            else
                pn = size(xm,2);
                pm = max(pr,[],2)*(1:pn)./pn - min(pr,[],2)*((1:pn)./pn - 1.0);
                pr = min(pr,[],2);
            end;
            nf(13) = 1;
        end;

        if(nf(9)) # parameter centering
            pr = mean(pm,2);
            pm = bsxfun(@minus,pm,pr);
        end;

        if(any(any(pm==0))), error('ERROR! emgr: zero parameter scales!'); end;
    end;

## STATE-SPACE SETUP

    if(w=='c' || w=='o' || w=='x' || w=='y')

        C = size(um,2); # number of input scales
        D = size(xm,2); # number of state scales

        switch(nf(1)) # residuals
            case 1, # mean state
                res = @(d) mean(d,2);
            case 2, # median state
                res = @(d) median(d,2);
            case 3, # steady state
                res = @(d) d(:,end);
            case 4, # pod
                res = @(d) pod1(d);
            case 5, # pca
                res = @(d) pod1(bsxfun(@minus,d,mean(d,2)));
            otherwise, # zero state
                res = @(d) zeros(size(d,1),1);
        end;

        switch(nf(6))
            case 1, # double run
                nf(6) = 0;
                WT = emgr(f,g,s,t,w,pr,nf,ut,us,xs,um,xm,yd);
                TX = sqrt(diag(WT));
                if(nf(13)), TX = TX(1:N-P); end;
                tx = 1.0./TX;
                F = f; f = @(x,u,p) TX.*F(tx.*x,u,p);
                G = g; g = @(x,u,p)     G(tx.*x,u,p);
            case 2, # scaled run
                TU = us(:,1);
                TX = xs;
                if(nf(13)), TX = TX(1:N-P); end;
                TU(TU==0) = 1.0; tu = 1.0./TU;
                TX(TX==0) = 1.0; tx = 1.0./TX;
                F = f; f = @(x,u,p) TX.*F(tx.*x,tu.*u,p);
                G = g; g = @(x,u,p)     G(tx.*x,tu.*u,p);
        end;

        if(nf(7)) # data driven
            if(size(yd,1)==1 && (w=='o'||w=='x')), yd = {[];yd{:}}; end;
            C = size(yd,2); um = ones(J,C);
            D = size(yd,2); xm = ones(N,D);
        else
            yd = cell(2,max(C,D));
        end;

        if(nf(8)) # robust parameter
            J = J + P;
            ut = [ut;ones(P,T)];
            us = [us;repmat(pr,[1,T])];
            um = [um;pm];
            if(w=='y'), xm = [xm;pm]; end;
            F = f; f = @(x,u,p) F(x,u(1:J-P),u(J-P+1:J));
            G = g; g = @(x,u,p) G(x,u(1:J-P),u(J-P+1:J));
        end;

        if(any(any(um==0))), error('ERROR! emgr: zero input scales!'); end;
        if(any(any(xm==0))), error('ERROR! emgr: zero state scales!'); end;

        W = zeros(N-(w=='x' && nf(13))*P,N); # preallocate gramian; 'single'
    end;

## GRAMIAN COMPUTATION

    switch(w) # by empirical gramian types

        case 'c', # controllability gramian
            for q=1:Q
                pp = pr(:,q);
                for c=1:C
                    for j=1:J # parfor
                        uu = us + bsxfun(@times,ut,sparse(j,1,um(j,c),J,1));
                        x = ode(f,1,h,T,xs,uu,pp,yd{1,c},0,nf(12));
                        x = (x-res(x))*(1.0/um(j,c));
                        W += (x*x'); # huma
                    end;
                end;
            end;
            W *= h/(C*Q);

        case 'o', # observability gramian
            o = zeros(O*T,N);
            for q=1:Q
                pp = pr(:,q);
                for d=1:D
                    for n=1:N # parfor
                        xx = xs + sparse(n,1,xm(n,d),N,1);
                        y = ode(f,g,h,T,xx,us,pp,yd{2,d},nf(13),nf(12));
                        y = (y-res(y))*(1.0/xm(n,d));
                        o(:,n) = reshape(y,[O*T,1]);
                    end;
                    W += (o'*o); # huma
                end;
            end;
            W *= h/(D*Q);

        case 'x', # cross gramian
            o = zeros(O,T,N);
            if(J~=O && ~nf(10)), error('ERROR! emgr: non-square system!'); end;
            for q=1:Q
                pp = pr(:,q);
                for d=1:D
                    for n=1:N # parfor
                        xx = xs + sparse(n,1,xm(n,d),N,1);
                        y = ode(f,g,h,T,xx,us,pp,yd{2,d},nf(13),nf(12));
                        o(:,:,n) = (y-res(y))*(1.0/xm(n,d));
                    end;
                    o = permute(o,[2,3,1]);
                    for c=1:C
                        for j=1:J # parfor
                            uu = us + bsxfun(@times,ut,sparse(j,1,um(j,c),J,1));
                            x = ode(f,1,h,T,xs,uu,pp,yd{1,c},nf(13),nf(12));
                            x = (x-res(x))*(1.0/um(j,c));
                            if(nf(10)), K = 1:O; else K = j; end;
                            for k=K
                                W += (x*o(:,:,k)); # huma
                            end;
                        end;
                    end;
                    o = reshape(o,O,T,N);
                end;
            end;
            W *= h/(C*D*Q);

        case 'y', # linear cross gramian
            if(J~=O && ~nf(8)), error('ERROR! emgr: non-square system!'); end;
            for q=1:Q
                pp = pr(:,q);
                for c=1:C
                    for j=1:J # parfor
                        uu = us + bsxfun(@times,ut,sparse(j,1,um(j,c),J,1));
                        yy = us + bsxfun(@times,ut,sparse(j,1,xm(j,c),J,1));
                        x = ode(f,1,h,T,xs,uu,pp,yd{1,c},0,nf(12));
                        y = ode(g,1,h,T,xs,yy,pp,yd{2,c},0,nf(12));
                        x = (x-res(x))*(1.0/um(j,c));
                        y = (y-res(y))*(1.0/xm(j,c));
                        W += (x*y'); # huma
                    end;
                end;
            end;
            W *= h/(C*Q);

        case 's', # sensitivity gramian
            W = cell(1,2);
            ps = sparse(P,1);
            nf(8) = 0;
            W{1} = emgr(f,g,[J,N,O],t,'c',pr,nf,ut,us,xs,um,xm);
            W{2} = speye(P);
            F = @(x,u,p) f(x,us(:,1),pr + p*u);
            G = @(x,u,p) g(x,us(:,1),pr + p*u);
            up = ones(1,T);
            ps = speye(P);
            for p=1:P
                V = emgr(F,G,[1,N,O],t,'c',ps(:,p),nf,up,0,xs,pm(p,:),xm);
                W{1} += V;            # approximate controllability gramian
                W{2}(p,p) = trace(V); # sensitivity gramian
            end;
            if(nf(10))
                W{2} -= mean(diag(W{2}));
            end;

        case 'i', # identifiability gramian
            W = cell(1,2);
            ps = sparse(P,1);
            V = emgr(f,g,[J,N+P,O],t,'o',ps,nf,ut,us,[xs;pr],um,[xm;pm]);
            W{1} = V(1:N,1:N);         # observability gramian
            W{2} = V(N+1:N+P,N+1:N+P); # approximate identifiability gramian
            if(nf(10))
                W{2} -= V(N+1:N+P,1:N)*ainv(W{1})*V(1:N,N+1:N+P);
            end;

        case 'j', # joint gramian
            W = cell(1,2);
            ps = sparse(P,1);
            V = emgr(f,g,[J,N+P,O],t,'x',ps,nf,ut,us,[xs;pr],um,[xm;pm]);
            W{1} = V(1:N,1:N); # cross gramian
            #W{2} = zeros(P);   # cross-identifiability gramian
            W{2} = -0.5*V(1:N,N+1:N+P)'*ainv(W{1}+W{1}')*V(1:N,N+1:N+P);

        otherwise,
            error('ERROR! emgr: unknown gramian type!');
    end;

    if(nf(11) && (w=='c'||w=='o'||w=='x'||w=='y') ), W = 0.5*(W+W'); end;
end

## ======== SCALING SELECTOR ========
function s = scales(s,d,e)

    switch(d)
        case 0, # linear
            s = s*[0.25,0.50,0.75,1.0];
        case 1, # logarithmic
            s = s*[0.001,0.01,0.1,1.0];
        case 2, # geometric
            s = s*[0.125,0.25,0.5,1.0];
        otherwise, # single
            #s = s;
    end;

    switch(e)
        case 1, # reciproce
            s = [1.0./s,s];
        case 2, # dyadic
            s = s*s';
        case 3, # single
            #s = s;
        otherwise, # unit
            s = [-s,s];
    end;
end

## ======== PRINCIPAL DIRECTION ========
function x = pod1(d)

    [x,D,V] = svds(d,1);
end

## ======== FAST APPROXIMATE INVERSION ========
function x = ainv(m)

    d = 1.0./diag(m);
    n = numel(d);
    x = bsxfun(@times,m,-d);
    x = bsxfun(@times,x,d');
    x(1:n+1:end) = d;
end

## ======== ODE INTEGRATOR ========
function x = ode(f,g,h,T,z,u,p,d,a,O)

    if(~isempty(d)), x = d; return; end; # Data-Driven

    N = numel(z);
    if(a), N = N - numel(p); p = z(N+1:end); z = z(1:N); end;

    if(O==-1) # Custom Solver
        global CUSTOM_ODE;

        if(isnumeric(g) && g==1) # Compute State Trajectory
            x = CUSTOM_ODE(f,h,T,z,u,p);
        else # Compute Output Trajectory
            v = CUSTOM_ODE(f,h,T,z,u,p);

            x(:,1) = g(v(:,1),u(:,1),p);
            x(end,T) = 0;

            for t=2:T
                x(:,t) = g(v(:,t),u(:,t),p);
            end;
        end;

    else # (Accelerated) Improved Runge-Kutta Method (IRK3)
        k1 = h*f(z,u(:,1),p);
        k2 = h*f(z + 0.5*k1,u(:,1),p);
        k3r = h*f(z + 0.75*k2,u(:,1),p);
        z += (2.0/9.0)*k1 + (1.0/3.0)*k2 + (4.0/9.0)*k3r; # Ralston (RK3)

        if(isnumeric(g) && g==1) # Compute State Trajectory
            x(:,1) = z;
            x(end,T) = 0;

            for t=2:T
                l1 = h*f(z,u(:,t),p);
                l2 = h*f(z + 0.5*l1,u(:,t),p);
                z += (2.0/3.0)*l1 + (1.0/3.0)*k1 + (5.0/6.0)*(l2 - k2);
                x(:,t) = z;
                k1 = l1;
                k2 = l2;
            end;
        else # Compute Output Trajectory
            x(:,1) = g(z,u(:,1),p);
            x(end,T) = 0;

            for t=2:T
                l1 = h*f(z,u(:,t),p);
                l2 = h*f(z + 0.5*l1,u(:,t),p);
                z += (2.0/3.0)*l1 + (1.0/3.0)*k1 + (5.0/6.0)*(l2 - k2);
                x(:,t) = g(z,u(:,t),p);
                k1 = l1;
                k2 = l2;
            end;
        end;
    end;
end

