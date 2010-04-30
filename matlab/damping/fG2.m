function [G2] = fG2(f, vperp, vpar, kperp, kpar, w, m, wch)
% f = distribution function, a function handle that takes as input 
%     (vperp,vpar) and returns the value of the distribution at that
%     point.
% vperp:  perpendicular velocity
% vpar:   parallel velocity
% kperp:  perpendicular component of k vector
% kpar:   parallel component of k vector
% w:      frequency, rad/s
% m:      resonance (0=landau, -1,+1=cyclotron, etc.)
% wch:    hot (signed) gyrofrequency, negative for electrons
  
DEL=1e-8;

d = DEL*abs(vperp);
if( d < 10*eps )
  d = 10*eps;
end;
df_dvperp = (f(vperp+d, vpar)-f(vperp-d,vpar))/(2*d);
d = DEL*abs(vpar);
if( d < 10*eps )
  d = 10*eps;
end;
df_dvpar = (f(vperp, vpar+d)-f(vperp,vpar-d))/(2*d);
Jm = real(besselj(m, kperp*vperp/wch));

% Should this be -(m*wch) or +(m*wch).  Waiting on Chen to get back to me
G2 = Jm*(df_dvpar-(m*wch+eps)/(w*vperp+eps)*(vpar*df_dvperp - vperp*df_dvpar));
