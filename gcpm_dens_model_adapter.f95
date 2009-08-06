! This module implements an adapter for GCPM with a dipole magnetic
! field in solar magnetic (SM) coordinates
module gcpm_dens_model_adapter
  use util
  use constants, only : R_E, PI
  use bmodel_dipole
  implicit none

  ! Types for marshalling.  This is required since the user of this adapter
  ! needs to set additional data for this adapter that is not in the 
  ! interface for funcPlasmaParams() used by the raytracer.
  type :: gcpmStateData
     !	itime	integer*4	dimensions=2
     !		(1) = yearday, e.g. 2001093
     !		(2) = miliseconds of day
     integer*4 :: itime(2)
     !		planetary Kp index
     real*4 :: akp
     ! Tsyganenko parameters
     real*8 :: Pdyn, Dst, ByIMF, BzIMF
     ! Whether to use (1) or not use (0) the tsyganenko corrections
     integer*4 :: use_tsyganenko
     ! Whether to use (1) IGRF or not use (0) and use dipole instead
     integer*4 :: use_igrf
  end type gcpmStateData
  ! Pointer container type.  This is the data that is actually marshalled.
  type :: gcpmStateDataP 
     type(gcpmStateData), pointer :: p
  end type gcpmStateDataP

  ! Imported from geopack
  real*4 :: PSI
  COMMON /GEOPACK1/ PSI

contains

  ! Implementation of the plasma parameters function.
  ! Inputs:
  !   x - position vector in cartesian (SM) coordinates
  ! Outputs:
  !  qs - vector of species charges
  !  Ns - vector of species densities in m^-3
  !  ms - vector of species masses in kg
  ! nus - vector of species collisions in s^-1
  ! In/out:
  ! funcPlasmaParamsData - arbitrary callback data 
  subroutine funcPlasmaParams(x, qs, Ns, ms, nus, B0, funcPlasmaParamsData)
    implicit none

    real*8, allocatable :: qs(:), Ns(:), ms(:), nus(:)
    real*8 :: B0(3), B0tmp(3), B0tmp2(3)
    character :: funcPlasmaParamsData(:)

    real*8 :: p_sm(3)
    real*8 :: ce,ch,che,co
    real*8 :: x(3),x_gsm(3)
    
    real*8 :: r, amlt, alatr
    real*4 :: outn(4)

    integer*4 :: year, day, hour, min, sec

    real*8 :: parmod(10)

    integer*4 :: iopt
    real*4 :: B0xTsy, B0yTsy, B0zTsy
    real*4 :: B0xBASE, B0yBASE, B0zBASE



    type(gcpmStateDataP) :: datap

    iopt = 0

    ! Unmarshall the callback data
    datap = transfer(funcPlasmaParamsData, datap)

    ! Allocate data if not already
    if (.not.(allocated(qs))) then
       allocate(qs(4))
    end if
    if (.not.(allocated(Ns))) then
       allocate(Ns(4))
    end if
    if (.not.(allocated(ms))) then
       allocate(ms(4))
    end if
    if (.not.(allocated(nus))) then
       allocate(nus(4))
    end if
    
    ! Convert from SM x,y,z to GSM x,y,z needed by 
    ! the Tsyganenko model
    call SM_TO_GSM_d(datap%p%itime,x,x_gsm)
    
    ! convert to spherical coordinates
    p_sm = cartesian_to_spherical(x)
    ! Convert magnetic r,theta,phi to SM local time in hours
    amlt = mod(24.0_8*p_sm(2)/(2.0_8*pi)+12.0_8,24.0_8)
    ! compute r, the geocentric distance in RE
    r = p_sm(1)/R_E
    ! Convert magnetic r,theta,phi to SM latitude in radians
    alatr = pi/2.0_8 - p_sm(3)

    !cccccccccccccccccccccccccccccccccccccccccccccccccccccccccccc
    !	Input parameters:
    !
    !	itime	integer*4	dimensions=2
    !		(1) = yearday, e.g. 2001093
    !		(2) = miliseconds of day
    !	r		real*4		dimension=1
    !		geocentric radial distance in Re
    !	amlt	real*4		dimension=1
    !		solar magnetic local time in hours
    !	alatr	real*4		dimension=1
    !		solar magnetic latitude in radians
    !	akp		real*4		dimension=1
    !		planetary Kp index
    !cccccccccccccccccccccccccccccccccccccccccccccccccccccccccccc
    
    !cccccccccccccccccccccccccccccccccccccccccccccccccccccccccccc
    !	Output parameters:
    !	outn	real*4		dimensions=4
    !			(1) = total electron density in 1/cm^3
    !			(2) = total hydrogen density in 1/cm^3
    !			(3) = total helium density in 1/cm^3
    !			(4) = total oxygen density in 1/cm^3
    !cccccccccccccccccccccccccccccccccccccccccccccccccccccccccccc
    !print *, 'itime=', datap%p%itime, 'r=', r, 'amlt=', amlt, 'alatr=', alatr,'akp=',datap%p%akp, 'outn=',outn
    call gcpm_v24(datap%p%itime,real(r),real(amlt),&
         real(alatr),real(datap%p%akp),outn)
    
    ce = dble(outn(1))
    ch = dble(outn(2))
    che = dble(outn(3))
    co = dble(outn(4))
    if( ce == 0.0_8 ) then
       ce = 1e-12
    end if
    if( ch == 0.0_8 ) then
       ch = 1e-12
    end if
    if( che == 0.0_8 ) then
       che = 1e-12
    end if
    if( co == 0.0_8 ) then
       co = 1e-12
    end if
   
    qs = 1.602e-19_8*(/ -1.0_8, 1.0_8, 1.0_8, 1.0_8 /);
    ms = (/ 9.10938188e-31_8, 1.6726e-27_8, &
         4.0_8*1.6726e-27_8, 16.0_8*1.6726e-27_8 /);
    ! Convert to m^-3;
    Ns = 1.0e6_8*(/ ce, ch, che, co /);
    nus = (/ 0.0_8, 0.0_8, 0.0_8, 0.0_8 /);

    ! Tsyganenko magnetic field
    
    ! Convert the itime parameter into the Tsyganenko parameters
    year = datap%p%itime(1)/1000
    day = mod(datap%p%itime(1),1000)
    hour = datap%p%itime(2)/(1000*60*60)
    min = (datap%p%itime(2)-hour*(1000*60*60))/(1000*60)
    sec = (datap%p%itime(2)-hour*(1000*60*60)-min*(1000*60))/(1000)

    ! Set the Tsyganenko parameters
    parmod(1) = datap%p%Pdyn   !Pdyn:  between 0.5 and 10 nPa,
    parmod(2) = datap%p%Dst    !Dst:  between -100 and +20,
    parmod(3) = datap%p%ByIMF  !ByIMF: between -10 and +10 nT.
    parmod(4) = datap%p%BzIMF  !BzIMF: between -10 and +10 nT.

    ! Necessary call for the Tsyganenko geopack tools.  Also updates
    ! the common variable psi
    call tsy_recalc(year, day, hour, min, sec)
    if( datap%p%use_igrf == 1 ) then
       ! Find IGRF components in GSM coordinates
       call IGRF_GSM (&
            real(x_gsm(1)/R_E), real(x_gsm(2)/R_E), real(x_gsm(3)/R_E), &
            B0xBASE,B0yBASE,B0zBASE)
    else
       ! Find the dipole field in SM coordinates
       B0tmp = bmodel_cartesian( x )
       ! Rotate to GSM and convert to nT for convenience with below
       call SM_TO_GSM_d(datap%p%itime,B0tmp,B0tmp2)
       B0xBASE = real(1.0e9_8*B0tmp2(1))
       B0yBASE = real(1.0e9_8*B0tmp2(2))
       B0zBASE = real(1.0e9_8*B0tmp2(3))
    end if
    if( datap%p%use_tsyganenko == 1 ) then
       call T96_01( iopt, real(parmod), real(psi), &
            real(x_gsm(1)/R_E), real(x_gsm(2)/R_E), real(x_gsm(3)/R_E), &
            B0xTsy, B0yTsy, B0zTsy)
    else
       B0xTsy = 0.0
       B0yTsy = 0.0
       B0zTsy = 0.0
    end if
       
    ! Add the field and Tsyganenko corrections together and convert from
    ! nT to T
    B0tmp(1) = (B0xBASE+B0xTsy)*1.0e-9_8
    B0tmp(2) = (B0yBASE+B0yTsy)*1.0e-9_8
    B0tmp(3) = (B0zBASE+B0zTsy)*1.0e-9_8

    ! We're in GSM coordinates.  Rotate back to SM
    call GSM_TO_SM_d(datap%p%itime,B0tmp,B0)

    
  end subroutine funcPlasmaParams


end module gcpm_dens_model_adapter
