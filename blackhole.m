function blackhole(o)
% stable orbit parameter identification inside event horizon of black hole
% by Christian Himpe, 2013-2015 ( http://gramian.de )
% released under BSD 2-Clause License ( opensource.org/licenses/BSD-2-Clause )
%*

if(exist('emgr')~=2)
    disp('emgr framework is required. Download at http://gramian.de/emgr.m');
    return;
end

%% Setup

t = [0.0,0.005,5.0];
T = (t(3)-t(1))/t(2);
u = zeros(1,T);
R = 14;

% Planet
xu = [0.4;pi/2;0;0];
pu = [0.568;1.13;0.13;0.9982;0.05]; % E,L,Q,a,e

% Photon
xp = [0.2;pi/2;0;0];
EE = 0.568; %10.5
pp = [EE;1.38*EE;0.03*EE*EE;0.9982;0.05]; % E,L,Q,a,e

%% Main

Y = [irk3(@(x,u,p) orbit(x,u,p,0,1),@bl2c,t,xu,u,pu);... % Full Order Planet
     irk3(@(x,u,p) orbit(x,u,p,0,0),@bl2c,t,xp,u,pp)];   % Full Order Photon

fprintf('Parameters: E,L,Q,a,e\n');

% PLANET
WS = emgr(@(x,u,p) orbit(x,u,p,0,1),@bl2c,[0,4,3],t,'s',pu,[1,0,0,0,0,0,0,0,0,0,0,0],1,0,xu);
PLANET_SENSITIVITY = full(diag(WS{2}))

% PHOTON
WS = emgr(@(x,u,p) orbit(x,u,p,0,0),@bl2c,[0,4,3],t,'s',pp,[1,0,0,0,0,0,0,0,0,0,0,0],1,0,xp);
PHOTON_SENSITIVITY = full(diag(WS{2}))

%% Output

if(nargin==0), return; end
figure();
grid on;
hold on;
p0 = plot3(0,0,0,'*','Color','black');                     %singularity
p1 = plot3(Y(1,end),Y(2,end),Y(3,end),'*','Color','red');  %planet
p2 = plot3(Y(1,:),Y(2,:),Y(3,:),'Color','red');            %planet orbit
p3 = plot3(Y(4,end),Y(5,end),Y(6,end),'*','Color','blue'); %photon
p4 = plot3(Y(4,:),Y(5,:),Y(6,:),'Color','blue');           %photon orbit
l = legend([p0 p2 p4],'singularity','planet orbit','photon orbit');
set(l,'FontSize',5);
hold off;
xl = ceil(10*max([abs(Y(1,:)),abs(Y(4,:))]))*0.1;
yl = ceil(10*max([abs(Y(2,:)),abs(Y(5,:))]))*0.1;
zl = ceil(10*max([abs(Y(3,:)),abs(Y(6,:))]))*0.1;
set(gca,'Xlim',[-xl,xl],'Ylim',[-yl,yl],'Zlim',[-zl,zl]);
view(-30,30);
if(o==1), print('-dpng',[mfilename(),'.png']); end;

%% ======== Orbit ========

function x = orbit(x,u,p,w,m)

 E = p(1); % E
 L = p(2); % L
 Q = p(3); % Q
 a = p(4); % a
 e = p(5); % e

 % w (eps)
 % m (mu)

 D  = x(1)^2 - 2*x(1) + a^2 + e^2;
 S  = x(1)^2 + a^2*cos(x(2))^2;
 P  = E*(x(1)^2 + a^2) + e*w*x(1) - a*L;
 Vt = Q - cos(x(2))^2*(a^2*(m^2 - E^2) + L^2*sin(x(2))^(-2) );
 Vr = P^2 - D*(m^2*x(1)^2 + (L - a*E)^2 + Q);

 x = abs([ sqrt(Vr) ; sqrt(Vt) ; L*sin(x(2))^(-2)+a*(P/D-E) ; a*(L-a*E*sin(x(2))^2)+P/D*(x(1)^2+a^2) ]./S);

%% ======== Boyer-Lindquist to Cartesian ========

function y = bl2c(x,u,p)

 a = p(4);

 y = [ sqrt(x(1)^2+a^2)*sin(x(2))*cos(x(3)) ; sqrt(x(1)^2+a^2)*sin(x(2))*sin(x(3)) ; x(1)*cos(x(2)) ];

%% ======== Integrator ========

function y = irk3(f,g,t,x,u,p)

    h = t(2);
    T = round(t(3)/h);

    k1 = h*f(x,u(:,1),p);
    k2 = h*f(x + 0.5*k1,u(:,1),p);
    k3r = h*f(x + 0.75*k2,u(:,1),p);
    x = x + (2.0/9.0)*k1 + (1.0/3.0)*k2 + (4.0/9.0)*k3r; % Ralston RK3

    y(:,1) = g(x,u(:,1),p);
    y(end,T) = 0;

    for t=2:T
        l1 = h*f(x,u(:,t),p);
        l2 = h*f(x + 0.5*l1,u(:,t),p);
        x = x + (2.0/3.0)*l1 + (1.0/3.0)*k1 + (5.0/6.0)*(l2 - k2);
        y(:,t) = g(x,u(:,t),p);
        k1 = l1;
        k2 = l2;
    end;
