function y = mysolver(f,g,t,x,u,p)
% mysolver (sample custom ode solver for emgr)
% by Christian Himpe, 2014-2015 ( http://gramian.de )
% released under BSD 2-Clause License ( opensource.org/licenses/BSD-2-Clause )
%*
    h = t(2);
    L = round((t(3)-t(1))/h) + 1;

    T = t(1):t(2):t(3);
    U = @(t) u(:,1+min(floor(t/h),L-1));

    % Compute State Trajectory
    if(exist('OCTAVE_VERSION'))
        x = lsode(@(y,t) f(y,U(t),p),x,T);
    else
        [tdummy,x] = ode45(@(t,y) f(y,U(t),p),T,x);
    end;  

    x = x';

    if(isnumeric(g) && g==1),
        y = x;
    else % Compute Output Trajectory
        O = numel(g(x(:,1),u(:,1),p));
        y(O,L) = 0;
        for I=1:L
            y(:,I) = g(x(:,I),u(:,I),p);
        end;
    end
end
