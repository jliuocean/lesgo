!!
!!  Copyright (C) 2012-2013  Johns Hopkins University
!!
!!  This file is part of lesgo.
!!
!!  lesgo is free software: you can redistribute it and/or modify
!!  it under the terms of the GNU General Public License as published by
!!  the Free Software Foundation, either version 3 of the License, or
!!  (at your option) any later version.
!!
!!  lesgo is distributed in the hope that it will be useful,
!!  but WITHOUT ANY WARRANTY; without even the implied warranty of
!!  MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
!!  GNU General Public License for more details.
!!
!!  You should have received a copy of the GNU General Public License
!!  along with lesgo.  If not, see <http://www.gnu.org/licenses/>.
!!

module turbines_base
use types, only:rprec
use stat_defs, only:wind_farm
$if ($MPI)
  use mpi_defs
$endif

implicit none

! The following values are read from the input file
integer :: num_x            ! number of turbines in the x-direction
integer :: num_y            ! number of turbines in the y-direction

real(rprec) :: dia_all      ! baseline diameter in meters
real(rprec) :: height_all   ! baseline height in meters
real(rprec) :: thk_all      ! baseline thickness in meters

integer :: orientation      ! orientation 1=aligned, 2=horiz stagger,
                            !  3=vert stagger by row, 4=vert stagger checkerboard
real(rprec) :: stag_perc    ! stagger percentage from baseline

real(rprec) :: theta1_all   ! angle from upstream (CCW from above, -x dir is zero)
real(rprec) :: theta2_all   ! angle above horizontal

real(rprec) :: Ct_prime     ! thrust coefficient (default 1.33)
real(rprec) :: Ct_noprime   ! thrust coefficient (default 0.75)

real(rprec) :: T_avg_dim    ! disk-avg time scale in seconds (default 600)

real(rprec) :: alpha        ! filter size as multiple of grid spacing
integer :: trunc            ! Gaussian filter truncated after this many gridpoints
real(rprec) :: filter_cutoff  ! indicator function only includes values above this threshold

logical :: turbine_cumulative_time ! Used to read in the disk averaged velocities of the turbines

integer :: tbase     ! Number of timesteps between the output
 
! The following are derived from the values above
integer :: nloc             ! total number of turbines
real(rprec) :: sx           ! spacing in the x-direction, multiple of (mean) diameter
real(rprec) :: sy           ! spacing in the y-direction
real(rprec) :: dummy,dummy2 ! used to shift the turbine positions

!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!
contains
!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!
! This subroutine sets the values for wind_farm based on values
!   read from the input file.

subroutine turbines_base_init()
use param, only: L_x, L_y, dx, dy, dz, pi, z_i
implicit none

integer :: i, j, k
real(rprec) :: sxx, syy, shift_base, const

! set turbine parameters
! turbines are numbered as follows:
!   #1 = turbine nearest (x,y)=(0,0)
!   #2 = next turbine in the y-direction, etc. (go along rows)

    ! Allocate wind turbine array derived type
    nloc = num_x*num_y      !number of turbines (locations) 
    nullify(wind_farm%turbine)
    allocate(wind_farm%turbine(nloc))

    ! Non-dimensionalize length values by z_i
    dia_all = dia_all / z_i
    height_all = height_all / z_i
    thk_all = thk_all / z_i
    ! Resize thickness capture at least on plane of gridpoints
    thk_all = max ( thk_all, dx*1.01 )

    ! Set baseline values for size
    wind_farm%turbine(:)%height = height_all
    wind_farm%turbine(:)%dia = dia_all
    wind_farm%turbine(:)%thk = thk_all                      
    wind_farm%turbine(:)%vol_c =  dx*dy*dz/(pi/4.*(dia_all)**2 * thk_all)        

    ! Spacing between turbines (as multiple of mean diameter)
    sx = L_x / (num_x * dia_all )
    sy = L_y / (num_y * dia_all )

    ! Baseline locations (evenly spaced, not staggered aka aligned)
    !  x,y-locations
    k = 1
    sxx = sx * dia_all  ! x-spacing with units to match those of L_x
    syy = sy * dia_all  ! y-spacing
    do i = 1,num_x
      do j = 1,num_y
        wind_farm%turbine(k)%xloc = sxx*real(2*i-1)/2
        wind_farm%turbine(k)%yloc = syy*real(2*j-1)/2
        k = k + 1
      enddo
    enddo

    ! HERE PLACE TURBINES (x,y-positions) BASED ON 'ORIENTATION' FLAG
    if (orientation.eq.1) then
    ! Evenly-spaced, not staggered
    !  Use baseline as set above       
 
    elseif (orientation.eq.2) then
    ! Evenly-spaced, horizontally staggered only
      ! Shift each row according to stag_perc
      do i = 2, num_x
        do k = 1+num_y*(i-1), num_y*i         ! these are the numbers for turbines in row i
          shift_base = syy * stag_perc/100.
          wind_farm%turbine(k)%yloc = mod( wind_farm%turbine(k)%yloc + (i-1)*shift_base , L_y )
        enddo
      enddo
 
    elseif (orientation.eq.3) then 
    ! Evenly-spaced, only vertically staggered (by rows)
      ! Make even rows taller
      do i = 2, num_x, 2
        do k = 1+num_y*(i-1), num_y*i         ! these are the numbers for turbines in row i
          wind_farm%turbine(k)%height = height_all*(1.+stag_perc/100.)
        enddo
      enddo
      ! Make odd rows shorter
      do i = 1, num_x, 2
        do k = 1+num_y*(i-1), num_y*i         ! these are the numbers for turbines in row i
          wind_farm%turbine(k)%height = height_all*(1.-stag_perc/100.)
        enddo
      enddo
 
    elseif (orientation.eq.4) then        
    !Evenly-spaced, only vertically staggered, checkerboard pattern
      k = 1
      do i = 1, num_x 
        do j = 1, num_y
          const = 2.*mod(real(i+j),2.)-1.  ! this should alternate between 1, -1
          wind_farm%turbine(k)%height = height_all*(1.+const*stag_perc/100.)
          k = k + 1
        enddo
      enddo

    elseif (orientation.eq.5) then        
    !Aligned, but shifted forward for efficient use of simulation space during CPS runs

      ! Usual placement is baseline as set above

      ! Shift in spanwise direction: Note that stag_perc is now used
      k=1
      dummy=stag_perc*(wind_farm%turbine(2)%yloc - wind_farm%turbine(1)%yloc)
      do i = 1, num_x
      do j = 1, num_y
         dummy2=dummy*(i-1)         
         wind_farm%turbine(k)%yloc=mod(wind_farm%turbine(k)%yloc +dummy2,L_y)
         k=k+1
      enddo
      enddo
      
      ! Print the values to the file in order to check the turbine spacings
      k=1
      do i=1, num_x
      do j=1, num_y
        write(*,*) k,wind_farm%turbine(k)%xloc,wind_farm%turbine(k)%yloc
        k=k+1
      enddo
      enddo
      endif
            
    !orientation (angles)
    wind_farm%turbine(:)%theta1 = theta1_all
    wind_farm%turbine(:)%theta2 = theta2_all

end subroutine turbines_base_init

end module turbines_base
