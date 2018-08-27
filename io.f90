!!
!!  Copyright (C) 2009-2017  Johns Hopkins University
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

!*******************************************************************************
module io
!*******************************************************************************
use types, only : rprec
use param, only : ld, nx, ny, nz, nz_tot, path, coord, rank, nproc, jt_total
use param, only : total_time, total_time_dim, lbz, jzmin, jzmax
use param, only : cumulative_time, fcumulative_time
use sim_param , only : w, dudz, dvdz
use sgs_param , only : Cs_opt2
use string_util
use messages
#ifdef PPMPI
use mpi
#endif

#ifdef PPCGNS
use cgns
#ifdef PPMPI
use param, only: ierr
#endif
#endif

implicit none
save
private

public jt_total, openfiles, energy, output_loop, output_final, output_init,    &
    write_tau_wall_bot, write_tau_wall_top

! Where to end with nz index.
integer :: nz_end

contains

!*******************************************************************************
subroutine openfiles()
!*******************************************************************************
use param, only : use_cfl_dt, dt, cfl_f
use open_file_fid_mod
implicit none
logical :: exst

! Temporary values used to read time step and CFL from file
real(rprec) :: dt_r, cfl_r

if (cumulative_time) then
    inquire (file=fcumulative_time, exist=exst)
    if (exst) then
        open (1, file=fcumulative_time)
        read(1, *) jt_total, total_time, total_time_dim, dt_r, cfl_r
        close (1)
    else
        ! assume this is the first run on cumulative time
        if ( coord == 0 ) then
            write (*, *) '--> Assuming jt_total = 0, total_time = 0.0'
        end if
        jt_total = 0
        total_time = 0._rprec
        total_time_dim = 0._rprec
    end if
end if

! Update dynamic time stepping info if required; otherwise discard.
if ( use_cfl_dt ) then
    dt = dt_r
    cfl_f = cfl_r
end if

end subroutine openfiles

!*******************************************************************************
subroutine energy (ke)
!*******************************************************************************
use types, only : rprec
use param
use sim_param, only : u, v, w
use messages
implicit none
integer :: jx, jy, jz, nan_count
real(rprec) :: KE, temp_w
real(rprec) :: ubulk, ubulk_global
#ifdef PPMPI
real(rprec) :: ke_global
#endif

! Initialize variables
nan_count = 0
ke = 0._rprec

do jz = 1, nz-1
do jy = 1, ny
do jx = 1, nx
    temp_w = 0.5_rprec*(w(jx,jy,jz)+w(jx,jy,jz+1))
    ke = ke + (u(jx,jy,jz)**2+v(jx,jy,jz)**2+temp_w**2)
end do
end do
end do

! Perform spatial averaging
ke = ke*0.5_rprec/(nx*ny*(nz-1))

! ubulk calculation
ubulk = 0
do jx = 1, nx
    do jy = 1, ny
        do jz = 1, nz-1
            ubulk = ubulk + u(jx,jy,jz)*dz
        end do
    end do
end do
ubulk = ubulk/(real(nx)*real(ny)*L_z)

#ifdef PPMPI
call mpi_reduce (ke, ke_global, 1, MPI_RPREC, MPI_SUM, 0, comm, ierr)
call mpi_reduce (ubulk, ubulk_global, 1, MPI_RPREC, MPI_SUM, 0, comm, ierr)

if (rank == 0) then  ! note that it's rank here, not coord
    ke = ke_global/nproc
    ubulk = ubulk_global
#endif
    open(2,file=path // 'output/check_ke.dat', status='unknown',               &
        form='formatted', position='append')
    if (jt_total==nenergy) then
        write(2,*) 'tstep    ','time   ','ke    ','ubulk    ','mean_p_force_x  '
    end if
    write(2,*) jt_total, total_time, ke, ubulk, mean_p_force_x
    close(2)
#ifdef PPMPI
end if
#endif

end subroutine energy

!*******************************************************************************
subroutine write_tau_wall_bot()
!*******************************************************************************
use types ,only: rprec
use param ,only: jt_total, total_time, total_time_dim, dt, dt_dim, wbase
use param ,only: L_x, z_i, u_star
use functions ,only: get_tau_wall_bot
implicit none

real(rprec) :: turnovers

open(2,file=path // 'output/tau_wall_bot.dat', status='unknown',               &
    form='formatted', position='append')

!! one time header output
if (jt_total==wbase) write(2,*)                                                &
    'jt_total, total_time, total_time_dim, turnovers, dt, dt_dim, 1.0, tau_wall'

!! continual time-related output
write(2,*) jt_total, total_time, total_time_dim, turnovers, dt, dt_dim,        &
    1.0, get_tau_wall_bot()
close(2)

end subroutine write_tau_wall_bot

!*******************************************************************************
subroutine write_tau_wall_top()
!*******************************************************************************
use types, only : rprec
use param, only : jt_total, total_time, total_time_dim, dt, dt_dim, wbase
use param, only : L_x, z_i, u_star
use functions, only : get_tau_wall_top
implicit none

real(rprec) :: turnovers

turnovers = total_time_dim / (L_x * z_i / u_star)

open(2,file=path // 'output/tau_wall_top.dat', status='unknown',               &
    form='formatted', position='append')

! one time header output
if (jt_total==wbase) write(2,*)                                                &
    'jt_total, total_time, total_time_dim, turnovers, dt, dt_dim, 1.0, tau_wall'

! continual time-related output
write(2,*) jt_total, total_time, total_time_dim, turnovers, dt, dt_dim,        &
    1.0, get_tau_wall_top()
close(2)

end subroutine write_tau_wall_top

#ifdef PPCGNS
#ifdef PPMPI
!*******************************************************************************
subroutine write_parallel_cgns (file_name, nx, ny, nz, nz_tot, start_n_in,     &
    end_n_in, xin, yin, zin, num_fields, fieldNames, input )
!*******************************************************************************
implicit none

integer, intent(in) :: nx, ny, nz, nz_tot, num_fields
! Name of file to be written
character(*), intent(in) :: file_name
! Name of fields we are writing
character(*), intent(in), dimension(:) :: fieldNames
! Data to be written
real(rprec), intent(in), dimension(:) :: input
! Coordinates to write
real(rprec), intent(in), dimension(:) :: xin, yin, zin
! Where the total node counter starts nodes
integer, intent(in) :: start_n_in(3)
! Where the total node counter ends nodes
integer, intent(in) :: end_n_in(3)

integer :: fn=1        ! CGNS file index number
integer :: ier         ! CGNS error status
integer :: base=1      ! base number
integer :: zone=1      ! zone number
integer :: nnodes      ! Number of nodes in this processor
integer :: sol =1      ! solution number
integer :: field       ! section number
integer(cgsize_t) :: sizes(3,3)  ! Sizes

! Convert input to right data type
integer(cgsize_t) :: start_n(3)  ! Where the total node counter starts nodes
integer(cgsize_t) :: end_n(3)  ! Where the total node counter ends nodes

! Building the lcoal mesh
integer :: i,j,k
real(rprec), dimension(nx,ny,nz) :: xyz

!  ! Set the parallel communicator
!  call cgp_mpi_comm_f(cgnsParallelComm, ierr)

! Convert types such that CGNS libraries can handle the input
start_n(1) = int(start_n_in(1), cgsize_t)
start_n(2) = int(start_n_in(2), cgsize_t)
start_n(3) = int(start_n_in(3), cgsize_t)
end_n(1) = int(end_n_in(1), cgsize_t)
end_n(2) = int(end_n_in(2), cgsize_t)
end_n(3) = int(end_n_in(3), cgsize_t)

! The total number of nodes in this processor
nnodes = nx*ny*nz

! Sizes, used to create zone
sizes(:,1) = (/int(nx, cgsize_t),int(ny, cgsize_t),int(nz_tot, cgsize_t)/)
sizes(:,2) = (/int(nx-1, cgsize_t),int(ny-1, cgsize_t),int(nz_tot-1, cgsize_t)/)
sizes(:,3) = (/int(0, cgsize_t) , int(0, cgsize_t), int(0, cgsize_t)/)

! Open CGNS file
call cgp_open_f(file_name, CG_MODE_WRITE, fn, ier)
if (ier .ne. CG_OK) call cgp_error_exit_f

! Write base
call cg_base_write_f(fn, 'Base', 3, 3, base, ier)
if (ier .ne. CG_OK) call cgp_error_exit_f

! Write zone
call cg_zone_write_f(fn, base, 'Zone', sizes, Structured, zone, ier)
if (ier .ne. CG_OK) call cgp_error_exit_f

! Write print info to screen
if (coord .eq. 0) then
    write(*,*) 'Writing, ', file_name
end if

! Create data nodes for coordinates
call cgp_coord_write_f(fn, base, zone, RealDouble, 'CoordinateX', nnodes, ier)
if (ier .ne. CG_OK) call cgp_error_exit_f

call cgp_coord_write_f(fn, base, zone, RealDouble, 'CoordinateY', nnodes, ier)
if (ier .ne. CG_OK) call cgp_error_exit_f

call cgp_coord_write_f(fn, base, zone, RealDouble, 'CoordinateZ', nnodes, ier)
if (ier .ne. CG_OK) call cgp_error_exit_f

! Write the coordinate data in parallel to the queue
!  call cgp_queue_set_f(1, ier)
!  if (ier .ne. CG_OK) call cgp_error_exit_f

! This is done for the 3 dimensions x,y and z
! It writes the coordinates
! Create grid points
do k = 1, nz
do j = 1, ny
do i = 1, nx
    xyz(i,j,k) = xin(i)
end do
end do
end do

call cgp_coord_write_data_f(fn, base, zone, 1,                                 &
    start_n, end_n, xyz(1:nx,1:ny,1:nz), ier)
if (ier .ne. CG_OK) call cgp_error_exit_f

! Write out the queued coordinate data
!  call cgp_queue_flush_f(ier)
!  if (ier .ne. CG_OK) call cgp_error_exit_f
!  call cgp_queue_set_f(0, ier)

! Write the coordinate data in parallel to the queue
!  call cgp_queue_set_f(1, ier)
!  if (ier .ne. CG_OK) call cgp_error_exit_f

do k = 1, nz
do j = 1, ny
do i = 1, nx
    xyz(i,j,k) = yin(j)
end do
end do
end do
call cgp_coord_write_data_f(fn, base, zone, 2,   &
    start_n, end_n, xyz(1:nx,1:ny,1:nz), ier)
if (ier .ne. CG_OK) call cgp_error_exit_f

! Write out the queued coordinate data
!  call cgp_queue_flush_f(ier)
!  if (ier .ne. CG_OK) call cgp_error_exit_f
!  call cgp_queue_set_f(0, ier)

! Write the coordinate data in parallel to the queue
!  call cgp_queue_set_f(1, ier)
!  if (ier .ne. CG_OK) call cgp_error_exit_f

do k = 1, nz
do j = 1, ny
do i = 1, nx
    xyz(i,j,k) = zin(k)
end do
end do
end do
call cgp_coord_write_data_f(fn, base, zone, 3,   &
                            start_n, end_n, xyz(1:nx,1:ny,1:nz), ier)
if (ier .ne. CG_OK) call cgp_error_exit_f

! Write out the queued coordinate data
!  call cgp_queue_flush_f(ier)
!  if (ier .ne. CG_OK) call cgp_error_exit_f
!  call cgp_queue_set_f(0, ier)

! Create a centered solution
call cg_sol_write_f(fn, base, zone, 'Solution', Vertex, sol, ier)
if (ier .ne. CG_OK) call cgp_error_exit_f

! Write the solution
do i=1,num_fields
    call cgp_field_write_f(fn, base, zone, sol, RealDouble, fieldNames(i),     &
        field, ier)
    if (ier .ne. CG_OK) call cgp_error_exit_f

    call cgp_field_write_data_f(fn, base, zone, sol, field, start_n, end_n,    &
        input((i-1)*nnodes+1:(i)*nnodes), ier)
    if (ier .ne. CG_OK) call cgp_error_exit_f

end do

! Close the file
call cgp_close_f(fn, ier)
if (ier .ne. CG_OK) call cgp_error_exit_f

end subroutine write_parallel_cgns

!*******************************************************************************
subroutine write_null_cgns (file_name, nx, ny, nz, nz_tot, start_n_in,         &
    end_n_in, xin, yin, zin, num_fields, fieldNames )
!*******************************************************************************
implicit none

integer, intent(in) :: nx, ny, nz, nz_tot, num_fields
! Name of file to be written
character(*), intent(in) :: file_name
! Name of fields we are writing
character(*), intent(in), dimension(:) :: fieldNames
! Coordinates to write
real(rprec), intent(in), dimension(:) :: xin, yin, zin
! Where the total node counter starts nodes
integer, intent(in) :: start_n_in(3)
! Where the total node counter ends nodes
integer, intent(in) :: end_n_in(3)

integer :: fn=1        ! CGNS file index number
integer :: ier         ! CGNS error status
integer :: base=1      ! base number
integer :: zone=1      ! zone number
integer :: nnodes      ! Number of nodes in this processor
integer :: sol =1      ! solution number
integer :: field       ! section number
integer(cgsize_t) :: sizes(3,3)  ! Sizes

! Convert input to right data type
integer(cgsize_t) :: start_n(3)  ! Where the total node counter starts nodes
integer(cgsize_t) :: end_n(3)  ! Where the total node counter ends nodes

! Building the lcoal mesh
integer :: i,j,k
real(rprec), dimension(nx,ny,nz) :: xyz

!  ! Set the parallel communicator
!  call cgp_mpi_comm_f(cgnsParallelComm, ierr)

! Convert types such that CGNS libraries can handle the input
start_n(1) = int(start_n_in(1), cgsize_t)
start_n(2) = int(start_n_in(2), cgsize_t)
start_n(3) = int(start_n_in(3), cgsize_t)
end_n(1) = int(end_n_in(1), cgsize_t)
end_n(2) = int(end_n_in(2), cgsize_t)
end_n(3) = int(end_n_in(3), cgsize_t)

! The total number of nodes in this processor
nnodes = nx*ny*nz

! Sizes, used to create zone
sizes(:,1) = (/int(nx, cgsize_t),int(ny, cgsize_t),int(nz_tot, cgsize_t)/)
sizes(:,2) = (/int(nx-1, cgsize_t),int(ny-1, cgsize_t),int(nz_tot-1, cgsize_t)/)
sizes(:,3) = (/int(0, cgsize_t) , int(0, cgsize_t), int(0, cgsize_t)/)

! Open CGNS file
call cgp_open_f(file_name, CG_MODE_WRITE, fn, ier)
if (ier .ne. CG_OK) call cgp_error_exit_f

! Write base
call cg_base_write_f(fn, 'Base', 3, 3, base, ier)
if (ier .ne. CG_OK) call cgp_error_exit_f

! Write zone
call cg_zone_write_f(fn, base, 'Zone', sizes, Structured, zone, ier)
if (ier .ne. CG_OK) call cgp_error_exit_f

! Write print info to screen
if (coord .eq. 0) then
    write(*,*) 'Writing, ', file_name
end if

! Create data nodes for coordinates
call cgp_coord_write_f(fn, base, zone, RealDouble, 'CoordinateX', nnodes, ier)
if (ier .ne. CG_OK) call cgp_error_exit_f

call cgp_coord_write_f(fn, base, zone, RealDouble, 'CoordinateY', nnodes, ier)
if (ier .ne. CG_OK) call cgp_error_exit_f

call cgp_coord_write_f(fn, base, zone, RealDouble, 'CoordinateZ', nnodes, ier)
if (ier .ne. CG_OK) call cgp_error_exit_f

! This is done for the 3 dimensions x,y and z
! It writes the coordinates
! Create grid points
do k = 1, nz
do j = 1, ny
do i = 1, nx
    xyz(i,j,k) = xin(i)
end do
end do
end do
write(*,*) "HERE 0.8"

call cgp_coord_write_data_f(fn, base, zone, 1, start_n, end_n, %VAL(0), ier)
write(*,*) "HERE 0.85"
if (ier .ne. CG_OK) call cgp_error_exit_f
write(*,*) "HERE 0.9"

! Write out the queued coordinate data
!  call cgp_queue_flush_f(ier)
!  if (ier .ne. CG_OK) call cgp_error_exit_f
!  call cgp_queue_set_f(0, ier)

! Write the coordinate data in parallel to the queue
!  call cgp_queue_set_f(1, ier)
!  if (ier .ne. CG_OK) call cgp_error_exit_f

do k = 1, nz
do j = 1, ny
do i = 1, nx
    xyz(i,j,k) = yin(j)
end do
end do
end do
call cgp_coord_write_data_f(fn, base, zone, 2, start_n, end_n, %VAL(0), ier)
if (ier .ne. CG_OK) call cgp_error_exit_f
write(*,*) "HERE 1.0"

! Write out the queued coordinate data
!  call cgp_queue_flush_f(ier)
!  if (ier .ne. CG_OK) call cgp_error_exit_f
!  call cgp_queue_set_f(0, ier)

! Write the coordinate data in parallel to the queue
!  call cgp_queue_set_f(1, ier)
!  if (ier .ne. CG_OK) call cgp_error_exit_f

do k = 1, nz
do j = 1, ny
do i = 1, nx
    xyz(i,j,k) = zin(k)
end do
end do
end do
write(*,*) "HERE 1.1"

call cgp_coord_write_data_f(fn, base, zone, 3, start_n, end_n, %VAL(0), ier)
if (ier .ne. CG_OK) call cgp_error_exit_f

! Create a centered solution
call cg_sol_write_f(fn, base, zone, 'Solution', Vertex, sol, ier)
if (ier .ne. CG_OK) call cgp_error_exit_f

! Write the solution
do i = 1, num_fields
    call cgp_field_write_f(fn, base, zone, sol, RealDouble, fieldNames(i),     &
                           field, ier)
    if (ier .ne. CG_OK) call cgp_error_exit_f

    call cgp_field_write_data_f(fn, base, zone, sol, field, start_n, end_n,    &
                                %VAL(0), ier)
    if (ier .ne. CG_OK) call cgp_error_exit_f

end do

! Close the file
call cgp_close_f(fn, ier)
if (ier .ne. CG_OK) call cgp_error_exit_f

write(*,*) "end of write_null_cgns"

end subroutine write_null_cgns
#endif
#endif

!*******************************************************************************
subroutine output_loop()
!*******************************************************************************
!
!  This subroutine is called every time step and acts as a driver for
!  computing statistics and outputing instantaneous data. No actual
!  calculations are performed here.
!
use param, only : jt_total, dt
use param, only : checkpoint_data, checkpoint_nskip
use param, only : tavg_calc, tavg_nstart, tavg_nend, tavg_nskip
use param, only : point_calc, point_nstart, point_nend, point_nskip
use param, only : domain_calc, domain_nstart, domain_nend, domain_nskip
use param, only : xplane_calc, xplane_nstart, xplane_nend, xplane_nskip
use param, only : yplane_calc, yplane_nstart, yplane_nend, yplane_nskip
use param, only : zplane_calc, zplane_nstart, zplane_nend, zplane_nskip
use param, only : zpert_calc, zpert_nstart, zpert_nend, zpert_nskip
use param, only : perte_calc, perte_nstart, perte_nend, perte_nskip
use param, only : pert_ntstep, pert_count, pert_current_tstep, pert_tstep
use stat_defs, only : tavg_initialized,tavg_dt
implicit none

! Determine if we are to checkpoint intermediate times
if( checkpoint_data ) then
    ! Now check if data should be checkpointed this time step
    if ( modulo (jt_total, checkpoint_nskip) == 0) call checkpoint()
end if

!  Determine if time summations are to be calculated
if (tavg_calc) then
    ! Are we between the start and stop timesteps?
    if ((jt_total >= tavg_nstart).and.(jt_total <= tavg_nend)) then
        ! Every timestep (between nstart and nend), add to tavg_dt
        tavg_dt = tavg_dt + dt

        ! Are we at the beginning or a multiple of nstart?
        if ( mod(jt_total-tavg_nstart,tavg_nskip)==0 ) then
            ! Check if we have initialized tavg
            if (.not.tavg_initialized) then
                if (coord == 0) then
                    write(*,*) '-------------------------------'
                    write(*,"(1a,i9,1a,i9)")                                   &
                        'Starting running time summation from ',               &
                        tavg_nstart, ' to ', tavg_nend
                    write(*,*) '-------------------------------'
                end if

                call tavg_init()
            else
                call tavg_compute ()
            end if
        end if
    end if
end if

!  Determine if instantaneous point velocities are to be recorded
if(point_calc) then
    if (jt_total >= point_nstart .and. jt_total <= point_nend .and.            &
        ( mod(jt_total-point_nstart,point_nskip)==0) ) then
        if (jt_total == point_nstart) then
            if (coord == 0) then
                write(*,*) '-------------------------------'
                write(*,"(1a,i9,1a,i9)")                                       &
                    'Writing instantaneous point velocities from ',            &
                    point_nstart, ' to ', point_nend
                write(*,"(1a,i9)") 'Iteration skip:', point_nskip
                write(*,*) '-------------------------------'
            end if
        end if
        call inst_write(1)
    end if
end if

!  Determine if instantaneous domain velocities are to be recorded
if(domain_calc) then
    if (jt_total >= domain_nstart .and. jt_total <= domain_nend .and.          &
        ( mod(jt_total-domain_nstart,domain_nskip)==0) ) then
        if (jt_total == domain_nstart) then
            if (coord == 0) then
                write(*,*) '-------------------------------'
                write(*,"(1a,i9,1a,i9)")                                       &
                    'Writing instantaneous domain velocities from ',           &
                    domain_nstart, ' to ', domain_nend
                write(*,"(1a,i9)") 'Iteration skip:', domain_nskip
                write(*,*) '-------------------------------'
            end if

        end if
        call inst_write(2)
    end if
end if

!  Determine if instantaneous x-plane velocities are to be recorded
if(xplane_calc) then
    if (jt_total >= xplane_nstart .and. jt_total <= xplane_nend .and.          &
        ( mod(jt_total-xplane_nstart,xplane_nskip)==0) ) then
    if (jt_total == xplane_nstart) then
        if (coord == 0) then
            write(*,*) '-------------------------------'
            write(*,"(1a,i9,1a,i9)")                                           &
                'Writing instantaneous x-plane velocities from ',              &
                xplane_nstart, ' to ', xplane_nend
            write(*,"(1a,i9)") 'Iteration skip:', xplane_nskip
            write(*,*) '-------------------------------'
            end if
        end if

        call inst_write(3)
    end if
end if

!  Determine if instantaneous y-plane velocities are to be recorded
if(yplane_calc) then
    if (jt_total >= yplane_nstart .and. jt_total <= yplane_nend .and.          &
        ( mod(jt_total-yplane_nstart,yplane_nskip)==0) ) then
        if (jt_total == yplane_nstart) then
            if (coord == 0) then
                write(*,*) '-------------------------------'
                write(*,"(1a,i9,1a,i9)")                                       &
                    'Writing instantaneous y-plane velocities from ',          &
                    yplane_nstart, ' to ', yplane_nend
                write(*,"(1a,i9)") 'Iteration skip:', yplane_nskip
                write(*,*) '-------------------------------'
            end if
        end if

        call inst_write(4)
    end if
end if

!  Determine if instantaneous z-plane velocities are to be recorded
if(zplane_calc) then
    if (jt_total >= zplane_nstart .and. jt_total <= zplane_nend .and.          &
        ( mod(jt_total-zplane_nstart,zplane_nskip)==0) ) then
        if (jt_total == zplane_nstart) then
            if (coord == 0) then
                write(*,*) '-------------------------------'
                write(*,"(1a,i9,1a,i9)")                                       &
                    'Writing instantaneous z-plane velocities from ',          &
                    zplane_nstart, ' to ', zplane_nend
                write(*,"(1a,i9)") 'Iteration skip:', zplane_nskip
                write(*,*) '-------------------------------'
            end if
        end if

        call inst_write(5)
    end if
end if


!  Determine if perturbation energy is to be recorded
if(perte_calc) then
    if (jt_total >= perte_nstart .and. jt_total <= perte_nend .and.          &
        ( mod(jt_total-perte_nstart,perte_nskip)==0) ) then
        if (jt_total == perte_nstart) then
            if (coord == 0) then
                write(*,*) '-------------------------------'
                write(*,"(1a,i9,1a,i9)")                                       &
                    'Writing perturbation energy from ',          &
                    perte_nstart, ' to ', perte_nend
                write(*,"(1a,i9)") 'Iteration skip:', perte_nskip
                write(*,*) '-------------------------------'
            end if
        end if
        call inst_write(6)
    end if
end if

!  Determine if instantaneous zplane pert. velocities are to be recorded
if(zpert_calc) then
    if ((jt_total >= zpert_nstart .and. jt_total <= zpert_nend .and.          &
        ( mod(jt_total-zpert_nstart,zpert_nskip)==0))                         &
        .or. jt_total == pert_current_tstep ) then
        if (jt_total == zpert_nstart) then
            if (coord == 0) then
                write(*,*) '-------------------------------'
                write(*,"(1a,i9,1a,i9)")                                       &
                    'Writing instantaneous z-plane instantaneous velocities from ',          &
                    zpert_nstart, ' to ', zpert_nend
                write(*,"(1a,i9)") 'Iteration skip:', zpert_nskip
                write(*,*) '-------------------------------'
            end if
        end if
        if (pert_count < pert_ntstep) then
            pert_count = pert_count + 1
        end if
        pert_current_tstep = pert_tstep(pert_count)
        call inst_write(7)
    end if
end if


end subroutine output_loop

!*******************************************************************************
subroutine inst_write(itype)
!*******************************************************************************
!
! This subroutine is used to write all of the instantaneous data from
! lesgo to file. The types of data written are:
!
!   points   : itype=1
!   domain   : itype=2
!   x-planes : itype=3
!   y-planes : itype=4
!   z-planes : itype=5
!   perte    : itype=6
!   zpert    : itype=7
!
! For the points and planar data, this subroutine writes using the
! locations specfied from the param module.
! If additional instantenous values are
! desired to be written, they should be done so using this subroutine.
!
use functions, only : linear_interp, trilinear_interp, interp_to_uv_grid
use param, only : point_nloc, point_loc
use param, only : xplane_nloc, xplane_loc
use param, only : yplane_nloc, yplane_loc
use param, only : zplane_nloc, zplane_loc
use param, only : dx,dy,dz,L_x,L_y,L_z
use param, only : write_endian
use param, only : comm, ierr, MPI_RPREC
use grid_m
use sim_param, only : u,v,w
use cfl_util, only : get_max_cfl
! For computing and writing vorticity
!  use sim_param, only: dwdy, dwdx, dvdx, dudy
!  use functions, only : interp_to_w_grid

use stat_defs, only : xplane, yplane, zplane
#ifdef PPMPI
use stat_defs, only : point
use param, only : ny, nz
#endif
#ifdef PPLVLSET
use level_set_base, only : phi
use sim_param, only : fx,fy,fz,fxa,fya,fza
#endif

implicit none

integer, intent(IN) :: itype
character (64) :: fname
character (64) :: fname2
integer :: n, i, j, k
real(rprec), allocatable, dimension(:,:,:) :: ui, vi, wi, w_uv
real(rprec), allocatable, dimension(:,:,:) :: up, vp, wp
real(rprec), allocatable, dimension(:) :: ubar, vbar, wbar
real(rprec), pointer, dimension(:) :: x,y,z,zw
real(rprec) :: pert_energy,xpert_energy,ypert_energy,zpert_energy
real(rprec) :: pert_energy_global
real(rprec) :: xpert_energy_global,ypert_energy_global,zpert_energy_global
real(rprec) :: ubulk, ubulk_global
real(rprec) :: umax_local, umax_global, upmax_local, upmax_global
real(rprec) :: vmax_local, vmax_global, vpmax_local, vpmax_global
real(rprec) :: wmax_local, wmax_global, wpmax_local, wpmax_global
real(rprec) :: maxcfl

#ifndef PPCGNS
character(64) :: bin_ext

#ifdef PPLVLSET
real(rprec), allocatable, dimension(:,:,:) :: fx_tot, fy_tot, fz_tot
#endif

#ifdef PPMPI
call string_splice(bin_ext, '.c', coord, '.bin')
#else
bin_ext = '.bin'
#endif
#endif

! #ifdef PPCGNS
! Vorticity
! real(rprec), dimension (:, :, :), allocatable :: vortx, vorty, vortz
! #endif

! Nullify pointers
nullify(x,y,z,zw)

! Set grid pointers
x => grid % x
y => grid % y
z => grid % z
zw => grid % zw

!  Allocate space for the interpolated values
allocate(w_uv(nx,ny,lbz:nz))

!  Make sure w has been interpolated to uv-grid
w_uv = interp_to_uv_grid(w(1:nx,1:ny,lbz:nz), lbz)

!  Instantaneous velocity sampled at point
if(itype==1) then
    do n = 1, point_nloc
        ! Common file name for all output types
        call string_splice(fname, path // 'output/vel.x-', point_loc(n)%xyz(1),&
            '.y-', point_loc(n)%xyz(2), '.z-', point_loc(n)%xyz(3), '.dat')

#ifdef PPMPI
        if(point(n) % coord == coord) then
#endif
            open(unit=13, position="append", file=fname)
            write(13,*) total_time,                                            &
            trilinear_interp(u(1:nx,1:ny,lbz:nz), lbz, point_loc(n)%xyz),      &
            trilinear_interp(v(1:nx,1:ny,lbz:nz), lbz, point_loc(n)%xyz),      &
            trilinear_interp(w_uv(1:nx,1:ny,lbz:nz), lbz, point_loc(n)%xyz)
            close(13)
#ifdef PPMPI
        end if
#endif
    end do

!  Instantaneous write for entire domain
elseif(itype==2) then
    ! Common file name for all output types
    call string_splice(fname, path //'output/vel.', jt_total)

#if defined(PPCGNS) && defined(PPMPI)
    ! Write CGNS Output
    call string_concat(fname, '.cgns')
    call write_parallel_cgns(fname,nx,ny, nz - nz_end, nz_tot,                 &
        (/ 1, 1,   (nz-1)*coord + 1 /),                                        &
        (/ nx, ny, (nz-1)*(coord+1) + 1 - nz_end /),                           &
        x(1:nx) , y(1:ny) , z(1:(nz-nz_end) ),                                 &
        3, (/ 'VelocityX', 'VelocityY', 'VelocityZ' /),                        &
        (/ u(1:nx,1:ny,1:(nz-nz_end)), v(1:nx,1:ny,1:(nz-nz_end)),             &
         w_uv(1:nx,1:ny,1:(nz-nz_end)) /) )
#else
    ! Write binary Output
    call string_concat(fname, bin_ext)
    open(unit=13, file=fname, form='unformatted', convert=write_endian,        &
        access='direct', recl=nx*ny*nz*rprec)
    write(13,rec=1) u(:nx,:ny,1:nz)
    write(13,rec=2) v(:nx,:ny,1:nz)
    write(13,rec=3) w_uv(:nx,:ny,1:nz)
    close(13)
#endif

!     ! Compute vorticity
!     allocate(vortx(nx,ny,lbz:nz), vorty(nx,ny,lbz:nz), vortz(nx,ny,lbz:nz))
!     vortx(1:nx,1:ny,lbz:nz) = 0._rprec
!     vorty(1:nx,1:ny,lbz:nz) = 0._rprec
!     vortz(1:nx,1:ny,lbz:nz) = 0._rprec
!
!     ! Use vorticityx as an intermediate step for performing uv-w interpolation
!     ! Vorticity is written in w grid
!     vortx(1:nx,1:ny,lbz:nz) = dvdx(1:nx,1:ny,lbz:nz) - dudy(1:nx,1:ny,lbz:nz)
!     vortz(1:nx,1:ny,lbz:nz) = interp_to_w_grid( vortx(1:nx,1:ny,lbz:nz), lbz)
!     vortx(1:nx,1:ny,lbz:nz) = dwdy(1:nx,1:ny,lbz:nz) - dvdz(1:nx,1:ny,lbz:nz)
!     vorty(1:nx,1:ny,lbz:nz) = dudz(1:nx,1:ny,lbz:nz) - dwdx(1:nx,1:ny,lbz:nz)
!
!     if (coord == 0) then
!        vortz(1:nx,1:ny, 1) = 0._rprec
!     end if
!
!     call string_splice(fname, path //'output/vorticity_', jt_total,'.cgns')
!
!     call write_parallel_cgns(fname,nx,ny, nz - nz_end, nz_tot,          &
!      (/ 1, 1,   (nz-1)*coord + 1 /),                                        &
!      (/ nx, ny, (nz-1)*(coord+1) + 1 - nz_end /),                           &
!      x(1:nx) , y(1:ny) , zw(1:(nz-nz_end) ),                                &
!      3, (/ 'VorticitX', 'VorticitY', 'VorticitZ' /),                        &
!      (/ vortx(1:nx,1:ny,1:(nz-nz_end)), vorty(1:nx,1:ny,1:(nz-nz_end)),     &
!       vortz(1:nx,1:ny,1:(nz-nz_end)) /) )
!
!      deallocate(vortx, vorty, vortz)


!  Write instantaneous x-plane values
elseif(itype==3) then

    allocate(ui(1,ny,nz), vi(1,ny,nz), wi(1,ny,nz))

    !  Loop over all xplane locations
    do i = 1, xplane_nloc
        do k = 1, nz
            do j = 1, ny
                ui(1,j,k) = linear_interp(u(xplane(i) % istart,j,k),    &
                     u(xplane(i) % istart+1,j,k), dx, xplane(i) % ldiff)
                vi(1,j,k) = linear_interp(v(xplane(i) % istart,j,k),    &
                     v(xplane(i) % istart+1,j,k), dx, xplane(i) % ldiff)
                wi(1,j,k) = linear_interp(w_uv(xplane(i) % istart,j,k), &
                     w_uv(xplane(i) % istart+1,j,k), dx, &
                     xplane(i) % ldiff)
            end do
        end do

        ! Common file name portion for all output types
        call string_splice(fname, path // 'output/vel.x-', xplane_loc(i), '.', jt_total)

#if defined(PPCGNS) && defined(PPMPI)
        ! Write CGNS Output
        call string_concat(fname, '.cgns')
        call write_parallel_cgns (fname,1,ny, nz - nz_end, nz_tot,     &
                        (/ 1, 1,   (nz-1)*coord + 1 /),                &
                        (/ 1, ny, (nz-1)*(coord+1) + 1 - nz_end /),    &
                    xplane_loc(i:i) , y(1:ny) , z(1:(nz-nz_end) ),     &
              3, (/ 'VelocityX', 'VelocityY', 'VelocityZ' /),          &
              (/ ui(1,1:ny,1:(nz-nz_end)), vi(1,1:ny,1:(nz-nz_end)),   &
                 wi(1,1:ny,1:(nz-nz_end)) /) )

#else
        ! Write binary output
        call string_concat(fname, bin_ext)
        open(unit=13,file=fname,form='unformatted',convert=write_endian, access='direct',recl=ny*nz*rprec)
        write(13,rec=1) ui
        write(13,rec=2) vi
        write(13,rec=3) wi
        close(13)
#endif
    end do

    deallocate(ui,vi,wi)

!  Write instantaneous y-plane values
elseif(itype==4) then

    allocate(ui(nx,1,nz), vi(nx,1,nz), wi(nx,1,nz))

    !  Loop over all yplane locations
    do j = 1, yplane_nloc
        do k = 1, nz
            do i = 1, nx

                ui(i,1,k) = linear_interp(u(i,yplane(j) % istart,k),           &
                     u(i,yplane(j) % istart+1,k), dy, yplane(j) % ldiff)
                vi(i,1,k) = linear_interp(v(i,yplane(j) % istart,k),           &
                     v(i,yplane(j) % istart+1,k), dy, yplane(j) % ldiff)
                wi(i,1,k) = linear_interp(w_uv(i,yplane(j) % istart,k),        &
                     w_uv(i,yplane(j) % istart+1,k), dy, yplane(j) % ldiff)
            end do
        end do

        ! Common file name portion for all output types
        call string_splice(fname, path // 'output/vel.y-', yplane_loc(j), '.', &
             jt_total)

#if defined(PPCGNS) && defined(PPMPI)
        call string_concat(fname, '.cgns')
        call write_parallel_cgns (fname,nx,1, nz - nz_end, nz_tot,             &
            (/ 1, 1,   (nz-1)*coord + 1 /),                                    &
            (/ nx, 1, (nz-1)*(coord+1) + 1 - nz_end /),                        &
            x(1:nx) , yplane_loc(j:j) , z(1:(nz-nz_end) ),                     &
            3, (/ 'VelocityX', 'VelocityY', 'VelocityZ' /),                    &
            (/ ui(1:nx,1,1:(nz-nz_end)), vi(1:nx,1,1:(nz-nz_end)),             &
            wi(1:nx,1,1:(nz-nz_end)) /) )
#else
        ! Write binary output
        call string_concat(fname, bin_ext)
        open(unit=13,file=fname,form='unformatted',convert=write_endian, access='direct',recl=nx*nz*rprec)
        write(13,rec=1) ui
        write(13,rec=2) vi
        write(13,rec=3) wi
        close(13)
#endif

    end do

    deallocate(ui,vi,wi)

!  Write instantaneous z-plane values
elseif (itype==5) then

    allocate(ui(nx,ny,1), vi(nx,ny,1), wi(nx,ny,1))

    !  Loop over all zplane locations
    do k = 1, zplane_nloc
        ! Common file name portion for all output types
        call string_splice(fname, path // 'output/vel.z-',                     &
                zplane_loc(k), '.', jt_total)

#ifdef PPCGNS
        call string_concat(fname, '.cgns')
#endif

#ifdef PPMPI
        if(zplane(k) % coord == coord) then
            do j = 1, Ny
                do i = 1, Nx
                    ui(i,j,1) = linear_interp(u(i,j,zplane(k) % istart),       &
                         u(i,j,zplane(k) % istart+1), dz, zplane(k) % ldiff)
                    vi(i,j,1) = linear_interp(v(i,j,zplane(k) % istart),       &
                         v(i,j,zplane(k) % istart+1), dz, zplane(k) % ldiff)
                    wi(i,j,1) = linear_interp(w_uv(i,j,zplane(k) % istart),    &
                         w_uv(i,j,zplane(k) % istart+1), dz, zplane(k) % ldiff)
                end do
            end do

#ifdef PPCGNS
            call warn("inst_write","Z plane writting is currently disabled.")
!            ! Write CGNS Data
!            ! Only the processor with data writes, the other one is written
!            ! using null arguments with 'write_null_cgns'
!            call write_parallel_cgns (fname ,nx, ny, 1, 1,                     &
!                (/ 1, 1,   1 /),                                               &
!                (/ nx, ny, 1 /),                                               &
!                x(1:nx) , y(1:ny) , zplane_loc(k:k), 3,                        &
!                (/ 'VelocityX', 'VelocityY', 'VelocityZ' /),                   &
!                (/ ui(1:nx,1:ny,1), vi(1:nx,1:ny,1), wi(1:nx,1:ny,1) /) )
#else
            call string_concat(fname, bin_ext)
            open(unit=13,file=fname,form='unformatted',convert=write_endian,   &
                            access='direct',recl=nx*ny*1*rprec)
            write(13,rec=1) ui(1:nx,1:ny,1)
            write(13,rec=2) vi(1:nx,1:ny,1)
            write(13,rec=3) wi(1:nx,1:ny,1)
            close(13)
#endif
        end if
#endif
    end do
    deallocate(ui,vi,wi)

!  Write instantaneous perturbation values
elseif (itype==6) then

    allocate(up(nx,ny,nz-1), vp(nx,ny,nz-1), wp(nx,ny,nz-1))
    allocate(ubar(nz-1), vbar(nz-1), wbar(nz-1))

    !  Loop over all zplane locations
    do k = 1, nz-1
        ubar(k) = 0._rprec
        vbar(k) = 0._rprec
        wbar(k) = 0._rprec
        do j = 1, ny
            do i = 1, nx               
                ubar(k) = ubar(k) + u(i,j,k)
                vbar(k) = vbar(k) + v(i,j,k)
                wbar(k) = wbar(k) + w_uv(i,j,k)
            end do
        end do
        ubar(k) = ubar(k)/nx/ny
        vbar(k) = vbar(k)/nx/ny
        wbar(k) = wbar(k)/nx/ny
        
        do j = 1, ny
            do i = 1, nx
                up(i,j,k) = u(i,j,k) - ubar(k)
                vp(i,j,k) = v(i,j,k) - vbar(k) 
                wp(i,j,k) = w_uv(i,j,k) - wbar(k)
            end do
        end do     
    end do
    
    ! Calculate local maxumum u,v,w and up,vp,wp
    umax_local = maxval(abs(u(1:nx,1:ny,1:nz-1)))
    vmax_local = maxval(abs(v(1:nx,1:ny,1:nz-1)))
    wmax_local = maxval(abs(w(1:nx,1:ny,1:nz-1)))
    upmax_local = maxval(abs(up(1:nx,1:ny,1:nz-1)))
    vpmax_local = maxval(abs(vp(1:nx,1:ny,1:nz-1)))
    wpmax_local = maxval(abs(wp(1:nx,1:ny,1:nz-1)))

    ! Calculate bulk velocity
    ubulk = 0._rprec
    do k = 1, nz-1
        ubulk = ubulk + ubar(k)*dz
    end do 
    call mpi_reduce(ubulk,ubulk_global,1,MPI_RPREC,MPI_SUM,0,  &
        comm,ierr)
    ubulk = ubulk_global/L_z

    ! Calculate perturbation energy
    pert_energy = 0._rprec
    xpert_energy = 0._rprec
    ypert_energy = 0._rprec
    zpert_energy = 0._rprec
    do k = 1, nz-1
        do j = 1, ny
            do i = 1, nx
                pert_energy = pert_energy+(up(i,j,k)**2+vp(i,j,k)**2+wp(i,j,k)**2)&
                              *(dx*dy*dz)
                xpert_energy = xpert_energy+up(i,j,k)**2*(dx*dy*dz)
                ypert_energy = ypert_energy+vp(i,j,k)**2*(dx*dy*dz)
                zpert_energy = zpert_energy+wp(i,j,k)**2*(dx*dy*dz)
            end do
        end do
    end do
    call mpi_reduce(pert_energy,pert_energy_global,1,MPI_RPREC,MPI_SUM,0,  &
        comm,ierr)
    call mpi_reduce(xpert_energy,xpert_energy_global,1,MPI_RPREC,MPI_SUM,0,  &
        comm,ierr)
    call mpi_reduce(ypert_energy,ypert_energy_global,1,MPI_RPREC,MPI_SUM,0,  &
        comm,ierr)
    call mpi_reduce(zpert_energy,zpert_energy_global,1,MPI_RPREC,MPI_SUM,0,  &
        comm,ierr)
    
    ! Find global maximum u and up
    call mpi_reduce(umax_local,umax_global,1,MPI_RPREC,MPI_MAX,0,  &
        comm,ierr) 
    call mpi_reduce(vmax_local,vmax_global,1,MPI_RPREC,MPI_MAX,0,  &
        comm,ierr) 
    call mpi_reduce(wmax_local,wmax_global,1,MPI_RPREC,MPI_MAX,0,  &
        comm,ierr) 
    call mpi_reduce(upmax_local,upmax_global,1,MPI_RPREC,MPI_MAX,0,  &
        comm,ierr)
    call mpi_reduce(vpmax_local,vpmax_global,1,MPI_RPREC,MPI_MAX,0,  &
        comm,ierr)
    call mpi_reduce(wpmax_local,wpmax_global,1,MPI_RPREC,MPI_MAX,0,  &
        comm,ierr)

    maxcfl = get_max_cfl()
    
    if (rank == 0) then
        pert_energy = pert_energy_global/L_x/L_y/L_z
        xpert_energy = xpert_energy_global/L_x/L_y/L_z
        ypert_energy = ypert_energy_global/L_x/L_y/L_z
        zpert_energy = zpert_energy_global/L_x/L_y/L_z

        open(unit=13,file=path//'output/pert_energy.dat',status='unknown',  &
            form='formatted',position='append')
        if (jt_total == 0) then
            write(13,*) 'tstep    ','total_time    ','t*ubulk/h    ',&
                 'E_tot    ','Eu    ','Ev    ','Ew    ',&
                 'ubulk    ','Umax    ','Vmax    ','Wmax    ',&
                 'upmax    ','vpmax    ','wpmax    ','CFL    '
        end if
        write(13,*) jt_total, total_time, total_time*ubulk, pert_energy,&
            xpert_energy, ypert_energy, zpert_energy, ubulk, &
            umax_global, vmax_global, wmax_global, upmax_global,&
            vpmax_global, wpmax_global, maxcfl
        close(13)
    end if

    deallocate(up,vp,wp)
    deallocate(ubar,vbar,wbar)


!  Write instantaneous perturbation values
elseif (itype==7) then

    allocate(up(nx,ny,nz-1), vp(nx,ny,nz-1), wp(nx,ny,nz-1))
    allocate(ubar(nz-1), vbar(nz-1), wbar(nz-1))

    !  Loop over all zplane locations
    do k = 1, nz-1
        ! Common file name portion for all output types
        call string_splice(fname, path // 'output/vel.zpert.', jt_total)

#ifdef PPMPI
        ubar(k) = 0._rprec
        vbar(k) = 0._rprec
        wbar(k) = 0._rprec
        do j = 1, ny
            do i = 1, nx               
                ubar(k) = ubar(k) + u(i,j,k)
                vbar(k) = vbar(k) + v(i,j,k)
                wbar(k) = wbar(k) + w_uv(i,j,k)
            end do
        end do
        ubar(k) = ubar(k)/nx/ny
        vbar(k) = vbar(k)/nx/ny
        wbar(k) = wbar(k)/nx/ny
        
        do j = 1, ny
            do i = 1, nx
                up(i,j,k) = u(i,j,k) - ubar(k)
                vp(i,j,k) = v(i,j,k) - vbar(k) 
                wp(i,j,k) = w_uv(i,j,k) - wbar(k)
            end do
        end do

        
#endif
    end do

    call string_concat(fname, bin_ext)
    open(unit=13,file=fname,form='unformatted',convert=write_endian,   &
                         access='direct',recl=nx*ny*(nz-1)*rprec)
    write(13,rec=1) up(1:nx,1:ny,1:nz-1)
    write(13,rec=2) vp(1:nx,1:ny,1:nz-1)
    write(13,rec=3) wp(1:nx,1:ny,1:nz-1)
    close(13)

    deallocate(up,vp,wp)
    deallocate(ubar,vbar,wbar)
else
    write(*,*) 'Error: itype not specified properly to inst_write!'
    stop
end if

deallocate(w_uv)
nullify(x,y,z,zw)

#ifdef PPLVLSET
contains
!*******************************************************************************
subroutine force_tot()
!*******************************************************************************
#ifdef PPMPI
use mpi_defs, only : mpi_sync_real_array, MPI_SYNC_DOWN
#endif
implicit none

! Zero bogus values
fx(:,:,nz) = 0._rprec
fy(:,:,nz) = 0._rprec
        call string_splice(fname, path // 'output/vel.bar.', jt_total)
fz(:,:,nz) = 0._rprec

!  Sum both the induced and applied forces
allocate(fx_tot(nx,ny,nz), fy_tot(nx,ny,nz), fz_tot(nx,ny,nz))

#ifdef PPTURBINES
fx_tot = fxa(1:nx,1:ny,1:nz)
fy_tot = fya(1:nx,1:ny,1:nz)
fz_tot = fza(1:nx,1:ny,1:nz)

#elif PPATM
fx_tot = fxa(1:nx,1:ny,1:nz)
fy_tot = fya(1:nx,1:ny,1:nz)
fz_tot = fza(1:nx,1:ny,1:nz)

#elif PPLVLSET
fx_tot = fx(1:nx,1:ny,1:nz)+fxa(1:nx,1:ny,1:nz)
fy_tot = fy(1:nx,1:ny,1:nz)+fya(1:nx,1:ny,1:nz)
fz_tot = fz(1:nx,1:ny,1:nz)+fza(1:nx,1:ny,1:nz)
#else
fx_tot = 0._rprec
fy_tot = 0._rprec
fz_tot = 0._rprec
#endif

#ifdef PPMPI
!  Sync forces
call mpi_sync_real_array( fx_tot, 1, MPI_SYNC_DOWN )
call mpi_sync_real_array( fy_tot, 1, MPI_SYNC_DOWN )
call mpi_sync_real_array( fz_tot, 1, MPI_SYNC_DOWN )
#endif

! Put fz_tot on uv-grid
fz_tot(1:nx,1:ny,1:nz) = interp_to_uv_grid( fz_tot(1:nx,1:ny,1:nz), 1 )

return
end subroutine force_tot
#endif

!*******************************************************************************
!subroutine pressure_sync()
!!*******************************************************************************
!use mpi_defs, only : mpi_sync_real_array, MPI_SYNC_DOWN
!use param, only : ld
!implicit none
!
!! Reset bogus values
!p(:,:,nz) = p(:,:,nz-1)
!dpdx(:,:,nz) = dpdx(:,:,nz-1)
!dpdy(:,:,nz) = dpdy(:,:,nz-1)
!dpdz(:,:,nz) = dpdz(:,:,nz-1)
!
!#ifdef PPMPI
!!  Sync pressure
!call mpi_sync_real_array( p, 0 , MPI_SYNC_DOWN )
!call mpi_sync_real_array( dpdx, 1 , MPI_SYNC_DOWN )
!call mpi_sync_real_array( dpdy, 1 , MPI_SYNC_DOWN )
!call mpi_sync_real_array( dpdz, 1 , MPI_SYNC_DOWN )
!#endif
!
!return
!end subroutine pressure_sync
!
!!*******************************************************************************
!subroutine RHS_sync()
!!*******************************************************************************
!use param, only : ld
!use mpi_defs, only : mpi_sync_real_array, MPI_SYNC_DOWN
!implicit none
!
!! Reset bogus values
!RHSx(:,:,nz) = RHSx(:,:,nz-1)
!RHSy(:,:,nz) = RHSy(:,:,nz-1)
!RHSz(:,:,nz) = RHSz(:,:,nz-1)
!
!#ifdef PPMPI
!!  Sync RHS
!call mpi_sync_real_array( RHSx, 0 , MPI_SYNC_DOWN )
!call mpi_sync_real_array( RHSy, 0 , MPI_SYNC_DOWN )
!call mpi_sync_real_array( RHSz, 0 , MPI_SYNC_DOWN )
!#endif
!
!return
!end subroutine RHS_sync

end subroutine inst_write

!*******************************************************************************
subroutine checkpoint ()
!*******************************************************************************
use iwmles
use param, only : nz, checkpoint_file, tavg_calc, lbc_mom
#ifdef PPMPI
use param, only : comm,ierr
#endif
use sim_param, only : u, v, w, RHSx, RHSy, RHSz
use sgs_param, only : Cs_opt2, F_LM, F_MM, F_QN, F_NN
use param, only : jt_total, total_time, total_time_dim, dt,use_cfl_dt,cfl,sgs_model,write_endian
use cfl_util, only : get_max_cfl
use stat_defs, only : tavg_initialized
use string_util, only : string_concat
#if PPUSE_TURBINES
use turbines, only : turbines_checkpoint
#endif

! HIT Inflow
#ifdef PPHIT
use hit_inflow, only : hit_write_restart
#endif

implicit none
character(64) :: fname
real(rprec) :: cfl_w

fname = checkpoint_file
#ifdef PPMPI
call string_concat( fname, '.c', coord )
#endif

!  Open vel.out (lun_default in io) for final output
open(11, file=fname, form='unformatted', convert=write_endian,                 &
    status='unknown', position='rewind')
write (11) u(:, :, 1:nz), v(:, :, 1:nz), w(:, :, 1:nz),                        &
    RHSx(:, :, 1:nz), RHSy(:, :, 1:nz), RHSz(:, :, 1:nz),                      &
    Cs_opt2(:,:,1:nz), F_LM(:,:,1:nz), F_MM(:,:,1:nz),                         &
    F_QN(:,:,1:nz), F_NN(:,:,1:nz)
close(11)

#ifdef PPMPI
call mpi_barrier( comm, ierr )
#endif

! Checkpoint time averaging restart data
if ( tavg_calc .and. tavg_initialized ) call tavg_checkpoint()

! Write time and current simulation state
! Set the current cfl to a temporary (write) value based whether CFL is
! specified or must be computed
if( use_cfl_dt ) then
    cfl_w = cfl
else
    cfl_w = get_max_cfl()
end if

!xiang check point for iwm
if(lbc_mom==3)then
    if (coord == 0) call iwm_checkPoint()
end if

#ifdef PPHIT
    if (coord == 0) call hit_write_restart()
#endif

#if PPUSE_TURBINES
call turbines_checkpoint
#endif

!  Update total_time.dat after simulation
if (coord == 0) then
    !--only do this for true final output, not intermediate recording
    open (1, file=fcumulative_time)
    write(1, *) jt_total, total_time, total_time_dim, dt, cfl_w
    close(1)
end if

end subroutine checkpoint

!*******************************************************************************
subroutine output_final()
!*******************************************************************************
use stat_defs, only : tavg_initialized
use param, only : tavg_calc
implicit none

! Perform final checkpoint
call checkpoint()

!  Check if average quantities are to be recorded
if (tavg_calc .and. tavg_initialized ) call tavg_finalize()

end subroutine output_final

!*******************************************************************************
subroutine output_init ()
!*******************************************************************************
!
!  This subroutine allocates the memory for arrays used for statistical
!  calculations
!
use param, only : dx, dy, dz, nx, ny, nz, lbz
use param, only : point_calc, point_nloc, point_loc
use param, only : xplane_calc, xplane_nloc, xplane_loc
use param, only : yplane_calc, yplane_nloc, yplane_loc
use param, only : zplane_calc, zplane_nloc, zplane_loc
use param, only : tavg_calc
use grid_m
use functions, only : cell_indx
use stat_defs, only : point, xplane, yplane, zplane
use stat_defs, only : tavg, tavg_zplane
#ifdef PPOUTPUT_EXTRA
use stat_defs, only : tavg_sgs
#endif
use stat_defs, only : type_set
use open_file_fid_mod
implicit none

integer :: i,j,k
real(rprec), pointer, dimension(:) :: x,y,z


#ifdef PPMPI
! This adds one more element to the last processor (which contains an extra one)
! Processor nproc-1 has data from 1:nz
! Rest of processors have data from 1:nz-1
if ( coord == nproc-1 ) then
    nz_end = 0
else
    nz_end = 1
end if
#else
nz_end = 0
#endif

nullify(x,y,z)

x => grid % x
y => grid % y
z => grid % z

if( tavg_calc ) then
    allocate(tavg(nx,ny,lbz:nz))
    allocate(tavg_zplane(nz))
#ifdef PPOUTPUT_EXTRA
    allocate(tavg_sgs(nx,ny,nz))
#endif

  ! Initialize the derived types tavg and tavg_zplane
    do k = 1, Nz
        do j = 1, Ny
        do i = 1, Nx
            call type_set( tavg(i,j,k), 0._rprec )
#ifdef PPOUTPUT_EXTRA
            call type_set( tavg_sgs(i,j,k), 0._rprec )
#endif
        end do
        end do
        call type_set( tavg_zplane(k), 0._rprec )
  end do
end if

! Initialize information for x-planar stats/data
if (xplane_calc) then
    allocate(xplane(xplane_nloc))
    xplane(:) % istart = -1
    xplane(:) % ldiff = 0.

    !  Compute istart and ldiff
    do i = 1, xplane_nloc
        xplane(i) % istart = cell_indx('i', dx, xplane_loc(i))
        xplane(i) % ldiff = xplane_loc(i) - x(xplane(i) % istart)
    end do
end if

! Initialize information for y-planar stats/data
if (yplane_calc) then
    allocate(yplane(yplane_nloc))
    yplane(:) % istart = -1
    yplane(:) % ldiff = 0.

    !  Compute istart and ldiff
    do j = 1, yplane_nloc
        yplane(j) % istart = cell_indx('j', dy, yplane_loc(j))
        yplane(j) % ldiff = yplane_loc(j) - y(yplane(j) % istart)
    end do
end if

! Initialize information for z-planar stats/data
if(zplane_calc) then
    allocate(zplane(zplane_nloc))

    !  Initialize
    zplane(:) % istart = -1
    zplane(:) % ldiff = 0.
    zplane(:) % coord = -1

    !  Compute istart and ldiff
    do k = 1, zplane_nloc

#ifdef PPMPI
        if (zplane_loc(k) >= z(1) .and. zplane_loc(k) < z(nz)) then
            zplane(k) % coord = coord
            zplane(k) % istart = cell_indx('k',dz,zplane_loc(k))
            zplane(k) % ldiff = zplane_loc(k) - z(zplane(k) % istart)
        end if
#else
        zplane(k) % coord = 0
        zplane(k) % istart = cell_indx('k',dz,zplane_loc(k))
        zplane(k) % ldiff = zplane_loc(k) - z(zplane(k) % istart)
#endif
    end do
end if

!  Open files for instantaneous writing
if (point_calc) then
    allocate(point(point_nloc))

    !  Intialize the coord values
    ! (-1 shouldn't be used as coord so initialize to this)
    point % coord=-1
    point % fid = -1

    do i = 1, point_nloc
        !  Find the processor in which this point lives
#ifdef PPMPI
        if (point_loc(i)%xyz(3) >= z(1) .and. point_loc(i)%xyz(3) < z(nz)) then
#endif

            point(i) % coord = coord

            point(i) % istart = cell_indx('i',dx,point_loc(i)%xyz(1))
            point(i) % jstart = cell_indx('j',dy,point_loc(i)%xyz(2))
            point(i) % kstart = cell_indx('k',dz,point_loc(i)%xyz(3))

            point(i) % xdiff = point_loc(i)%xyz(1) - x(point(i) % istart)
            point(i) % ydiff = point_loc(i)%xyz(2) - y(point(i) % jstart)
            point(i) % zdiff = point_loc(i)%xyz(3) - z(point(i) % kstart)

#ifdef PPMPI
        end if
#endif
    end do
end if

nullify(x,y,z)

end subroutine output_init

!*******************************************************************************
subroutine tavg_init()
!*******************************************************************************
!
!  This subroutine loads the tavg.out files
!
use messages
use param, only : read_endian
use stat_defs, only : tavg, tavg_total_time, tavg_dt, tavg_initialized
use stat_defs, only : operator(.MUL.)
#ifdef PPOUTPUT_EXTRA
use stat_defs, only : tavg_sgs, tavg_total_time_sgs
#endif
implicit none

character (*), parameter :: ftavg_in = path // 'tavg.out'
#ifdef PPOUTPUT_EXTRA
character (*), parameter :: ftavg_sgs_in = path // 'tavg_sgs.out'
#endif
#ifdef PPMPI
character (*), parameter :: MPI_suffix = '.c'
#endif
character (128) :: fname

logical :: exst

fname = ftavg_in
#ifdef PPMPI
call string_concat( fname, MPI_suffix, coord )
#endif

inquire (file=fname, exist=exst)
if (.not. exst) then
    !  Nothing to read in
    if (coord == 0) then
        write(*,*) ' '
        write(*,*)'No previous time averaged data - starting from scratch.'
    end if
    ! note: tavg was already initialized to zero in output_init routine
    tavg_total_time = 0._rprec
else
    open(1, file=fname, action='read', position='rewind', form='unformatted',  &
        convert=read_endian)
    read(1) tavg_total_time
    read(1) tavg
    close(1)
end if

#ifdef PPOUTPUT_EXTRA
fname = ftavg_sgs_in
#ifdef PPMPI
call string_concat( fname, MPI_suffix, coord )
#endif

inquire (file=fname, exist=exst)
if (.not. exst) then
    !  Nothing to read in
    if(coord == 0) then
        write(*,*) ' '
        write(*,*)'No previous time averaged data (sgs) - starting from scratch.'
    end if

    tavg_total_time_sgs = 0._rprec
else
    open(1, file=fname, action='read', position='rewind', form='unformatted',  &
        convert=read_endian)
    read(1) tavg_total_time_sgs
    read(1) tavg_sgs
    close(1)
end if
#endif

! Initialize tavg_dt
tavg_dt = 0._rprec

! Set global switch that tavg as been initialized
tavg_initialized = .true.

end subroutine tavg_init

!*******************************************************************************
subroutine tavg_compute()
!*******************************************************************************
!
!  This subroutine collects the stats for each flow
!  variable quantity
!
use stat_defs, only : tavg, tavg_total_time, tavg_dt
#ifdef PPOUTPUT_EXTRA
use stat_defs, only : tavg_sgs, tavg_total_time_sgs
use sgs_param
#endif
use param, only : nx, ny, nz, lbz, jzmax, ubc_mom, lbc_mom
use sim_param, only : u, v, w
use sim_param, only : txx, txy, tyy, txz, tyz, tzz
!use sim_param, only : dudz, dvdz, dwdz
#ifdef PPTURBINES
use sim_param, only : fxa, fya, fza
#endif
use functions, only : interp_to_uv_grid, interp_to_w_grid

implicit none

integer :: i, j, k
real(rprec) :: u_p, u_p2, v_p, v_p2, w_p, w_p2
!real(rprec) :: dudz_p, dvdz_p, dwdz_p, dwdz_p2
real(rprec), allocatable, dimension(:,:,:) :: w_uv, u_w, v_w
!real(rprec), allocatable, dimension(:,:,:) :: dwdz_w

allocate(w_uv(nx,ny,lbz:nz), u_w(nx,ny,lbz:nz), v_w(nx,ny,lbz:nz))

w_uv(1:nx,1:ny,lbz:nz) = interp_to_uv_grid(w(1:nx,1:ny,lbz:nz), lbz )
u_w(1:nx,1:ny,lbz:nz) = interp_to_w_grid(u(1:nx,1:ny,lbz:nz), lbz )
v_w(1:nx,1:ny,lbz:nz) = interp_to_w_grid(v(1:nx,1:ny,lbz:nz), lbz )

!allocate(dwdz_w(nx,ny,lbz:nz))

!dwdz_w(1:nx,1:ny,lbz:nz) = interp_to_w_grid(w(1:nx,1:ny,lbz:nz), lbz )

! note: u_w not necessarily zero on walls, but only mult by w=0 vu u'w', so OK
! can zero u_w at BC anyway:
if(coord==0       .and. lbc_mom>0) u_w(:,:,1)  = 0._rprec
if(coord==nproc-1 .and. ubc_mom>0) u_w(:,:,nz) = 0._rprec
if(coord==0       .and. lbc_mom>0) v_w(:,:,1)  = 0._rprec
if(coord==nproc-1 .and. ubc_mom>0) v_w(:,:,nz) = 0._rprec

do k = lbz, jzmax     ! lbz = 0 for mpi runs, otherwise lbz = 1
do j = 1, ny
do i = 1, nx
    u_p = u(i,j,k)           !! uv grid
    u_p2= u_w(i,j,k)         !! w grid
    v_p = v(i,j,k)           !! uv grid
    v_p2= v_w(i,j,k)         !! w grid
    w_p = w(i,j,k)           !! w grid
    w_p2= w_uv(i,j,k)        !! uv grid
    !dudz_p = dudz(i,j,k)     !! w grid
    !dvdz_p = dvdz(i,j,k)     !! w grid
    !dwdz_p = dwdz(i,j,k)     !! uv grid
    !dwdz_p2 = dwdz_w(i,j,k) !! w grid

    tavg(i,j,k) % u = tavg(i,j,k) % u + u_p * tavg_dt !! uv grid
    tavg(i,j,k) % v = tavg(i,j,k) % v + v_p * tavg_dt !! uv grid
    tavg(i,j,k) % w = tavg(i,j,k) % w + w_p * tavg_dt !! w grid
    tavg(i,j,k) % w_uv = tavg(i,j,k) % w_uv + w_p2 * tavg_dt !! uv grid

    ! Note: compute u'w' on w-grid because stresses on w-grid --pj
    tavg(i,j,k) % u2 = tavg(i,j,k) % u2 + u_p * u_p * tavg_dt !! uv grid
    tavg(i,j,k) % v2 = tavg(i,j,k) % v2 + v_p * v_p * tavg_dt !! uv grid
    tavg(i,j,k) % w2 = tavg(i,j,k) % w2 + w_p * w_p * tavg_dt !! w grid
    tavg(i,j,k) % uv = tavg(i,j,k) % uv + u_p * v_p * tavg_dt !! uv grid
    tavg(i,j,k) % uw = tavg(i,j,k) % uw + u_p2 * w_p * tavg_dt !! w grid
    tavg(i,j,k) % vw = tavg(i,j,k) % vw + v_p2 * w_p * tavg_dt !! w grid

    tavg(i,j,k) % txx = tavg(i,j,k) % txx + txx(i,j,k) * tavg_dt !! uv grid
    tavg(i,j,k) % tyy = tavg(i,j,k) % tyy + tyy(i,j,k) * tavg_dt !! uv grid
    tavg(i,j,k) % tzz = tavg(i,j,k) % tzz + tzz(i,j,k) * tavg_dt !! uv grid
    tavg(i,j,k) % txy = tavg(i,j,k) % txy + txy(i,j,k) * tavg_dt !! uv grid
    tavg(i,j,k) % txz = tavg(i,j,k) % txz + txz(i,j,k) * tavg_dt !! w grid
    tavg(i,j,k) % tyz = tavg(i,j,k) % tyz + tyz(i,j,k) * tavg_dt !! w grid

    !tavg(i,j,k) % dudz = tavg(i,j,k) % dudz + dudz_p * tavg_dt !! w grid
    !tavg(i,j,k) % dvdz = tavg(i,j,k) % dvdz + dvdz_p * tavg_dt !! w grid
    !tavg(i,j,k) % dwdz = tavg(i,j,k) % dwdz + dwdz_p * tavg_dt !! uv grid
    !tavg(i,j,k) % dwdz_w = tavg(i,j,k) % dwdz_w + dwdz_p2 * tavg_dt !! w grid

#ifdef PPTURBINES
    tavg(i,j,k)%fx = tavg(i,j,k)%fx + fxa(i,j,k) * tavg_dt
    tavg(i,j,k)%fy = tavg(i,j,k)%fy + fya(i,j,k) * tavg_dt
    tavg(i,j,k)%fz = tavg(i,j,k)%fz + fza(i,j,k) * tavg_dt
#endif
end do
end do
end do

#ifdef PPOUTPUT_EXTRA
do k = 1, jzmax
do j = 1, ny
do i = 1, nx
    ! w-grid variables
    tavg_sgs(i,j,k)%Nu_t = tavg_sgs(i,j,k)%Nu_t + Nu_t(i,j,k) * tavg_dt
    tavg(i,j,k)%cs_opt2 = tavg(i,j,k)%cs_opt2 + Cs_opt2(i,j,k) * tavg_dt
end do
end do
end do
#endif

deallocate(w_uv)

! Update tavg_total_time for variable time stepping
tavg_total_time = tavg_total_time + tavg_dt
#ifdef PPOUTPUT_EXTRA
tavg_total_time_sgs = tavg_total_time_sgs + tavg_dt
#endif

! Set tavg_dt back to zero for next increment
tavg_dt = 0._rprec

end subroutine tavg_compute


!*******************************************************************************
subroutine tavg_finalize()
!*******************************************************************************
use grid_m
use stat_defs, only : tavg_t, tavg_total_time, tavg
use stat_defs, only : rs_t, rs!, tke_t, tke
use stat_defs, only : operator(.DIV.), operator(.MUL.)
use stat_defs, only : operator(.ADD.), operator(.SUB.)
use stat_defs, only : tavg_interp_to_uv_grid
use stat_defs, only : rs_compute, cnpy_tavg_mul!, tke_compute
use param, only : write_endian
#ifdef PPOUTPUT_EXTRA
use stat_defs, only : tavg_sgs, tavg_total_time_sgs
#endif
use param, only : ny,nz
#ifdef PPMPI
use mpi_defs, only : mpi_sync_real_array,MPI_SYNC_DOWNUP
use param, only : ierr,comm
#endif
implicit none

#ifndef PPCGNS
character(64) :: bin_ext
#endif

character(64) :: fname_vel, fname_velw, fname_vel2, fname_tau, fname_f
character(64) :: fname_rs, fname_cs, fname_sgs
!character(64) :: fname_deriv, fname_tke

integer :: i,j,k

real(rprec), pointer, dimension(:) :: x,y,z,zw

nullify(x,y,z,zw)

x => grid % x
y => grid % y
z => grid % z
zw => grid % zw

allocate(rs(nx,ny,lbz:nz))
!allocate(tke(nx,ny,lbz:nz))

! Common file name
fname_vel = path // 'output/veluv_avg'
fname_velw = path // 'output/velw_avg'
fname_vel2 = path // 'output/vel2_avg'
fname_tau = path // 'output/tau_avg'
fname_f = path // 'output/force_avg'
fname_rs = path // 'output/rs'
#ifdef PPOUTPUT_EXTRA
fname_cs = path // 'output/cs_opt2'
fname_sgs = path // 'output/sgs_avg'
#endif
!fname_deriv = path // 'output/deriv'
!fname_tke = path // 'output/tke'

! CGNS
#ifdef PPCGNS
call string_concat(fname_vel, '.cgns')
call string_concat(fname_velw, '.cgns')
call string_concat(fname_vel2, '.cgns')
call string_concat(fname_tau, '.cgns')
call string_concat(fname_f, '.cgns')
call string_concat(fname_rs, '.cgns')
#ifdef PPOUTPUT_EXTRA
call string_concat(fname_cs, '.cgns')
call string_concat(fname_sgs, '.cgns')
#endif
!call string_concat(fname_deriv, '.cgns')
!call string_concat(fname_tke, '.cgns')
! Binary
#else
#ifdef PPMPI
call string_splice(bin_ext, '.c', coord, '.bin')
#else
bin_ext = '.bin'
#endif
call string_concat(fname_vel, bin_ext)
call string_concat(fname_velw, bin_ext)
call string_concat(fname_vel2, bin_ext)
call string_concat(fname_tau, bin_ext)
call string_concat(fname_f, bin_ext)
call string_concat(fname_rs, bin_ext)
#ifdef PPOUTPUT_EXTRA
call string_concat(fname_cs, bin_ext)
call string_concat(fname_sgs, bin_ext)
#endif
!call string_concat(fname_deriv, bin_ext)
!call string_concat(fname_tke, bin_ext)
#endif

! Final checkpoint all restart data

#ifdef PPMPI
call mpi_barrier( comm, ierr )
#endif

!  Perform time averaging operation
!  tavg = tavg / tavg_total_time
do k = jzmin, jzmax
do j = 1, Ny
do i = 1, Nx
    tavg(i,j,k) = tavg(i,j,k) .DIV. tavg_total_time
end do
end do
end do

#ifdef PPOUTPUT_EXTRA
do k = 1, jzmax
do j = 1, Ny
do i = 1, Nx
    tavg_sgs(i,j,k) = tavg_sgs(i,j,k) .DIV. tavg_total_time_sgs
end do
end do
end do
#endif

#ifdef PPMPI
call mpi_barrier( comm, ierr )
#endif

!  Sync entire tavg structure
#ifdef PPMPI
call mpi_sync_real_array( tavg(1:nx,1:ny,lbz:nz)%u, 0, MPI_SYNC_DOWNUP )
call mpi_sync_real_array( tavg(1:nx,1:ny,lbz:nz)%v, 0, MPI_SYNC_DOWNUP )
call mpi_sync_real_array( tavg(1:nx,1:ny,lbz:nz)%w, 0, MPI_SYNC_DOWNUP )
call mpi_sync_real_array( tavg(1:nx,1:ny,lbz:nz)%u2, 0, MPI_SYNC_DOWNUP )
call mpi_sync_real_array( tavg(1:nx,1:ny,lbz:nz)%v2, 0, MPI_SYNC_DOWNUP )
call mpi_sync_real_array( tavg(1:nx,1:ny,lbz:nz)%w2, 0, MPI_SYNC_DOWNUP )
call mpi_sync_real_array( tavg(1:nx,1:ny,lbz:nz)%uw, 0, MPI_SYNC_DOWNUP )
call mpi_sync_real_array( tavg(1:nx,1:ny,lbz:nz)%vw, 0, MPI_SYNC_DOWNUP )
call mpi_sync_real_array( tavg(1:nx,1:ny,lbz:nz)%uv, 0, MPI_SYNC_DOWNUP )
call mpi_sync_real_array( tavg(1:nx,1:ny,lbz:nz)%fx, 0, MPI_SYNC_DOWNUP )
!call mpi_sync_real_array( tavg(1:nx,1:ny,lbz:nz)%dudz, 0, MPI_SYNC_DOWNUP )
!call mpi_sync_real_array( tavg(1:nx,1:ny,lbz:nz)%dvdz, 0, MPI_SYNC_DOWNUP )
!call mpi_sync_real_array( tavg(1:nx,1:ny,lbz:nz)%dwdz, 0, MPI_SYNC_DOWNUP )
!call mpi_sync_real_array( tavg(1:nx,1:ny,lbz:nz)%dwdz_w, 0, MPI_SYNC_DOWNUP )


#ifdef PPOUTPUT_EXTRA
call mpi_sync_real_array( tavg_sgs(1:nx,1:ny,lbz:nz)%Nu_t, 0, MPI_SYNC_DOWNUP )
call mpi_sync_real_array( tavg(1:nx,1:ny,lbz:nz)%cs_opt2, 0, MPI_SYNC_DOWNUP )
#endif
#endif

! Write all the 3D data
#ifdef PPCGNS
! Write CGNS Data
call write_parallel_cgns (fname_vel ,nx, ny, nz - nz_end, nz_tot,              &
    (/ 1, 1,   (nz-1)*coord + 1 /),                                            &
    (/ nx, ny, (nz-1)*(coord+1) + 1 - nz_end /),                               &
    x(1:nx) , y(1:ny) , z(1:(nz-nz_end) ), 3,                                  &
    (/ 'VelocityX', 'VelocityY', 'VelocityZ' /),                               &
    (/ tavg(1:nx,1:ny,1:nz - nz_end) % u,                                      &
       tavg(1:nx,1:ny,1:nz - nz_end) % v,                                      &
       tavg(1:nx,1:ny,1:nz- nz_end) % w_uv /) )

call write_parallel_cgns (fname_velw ,nx, ny, nz - nz_end, nz_tot,             &
    (/ 1, 1,   (nz-1)*coord + 1 /),                                            &
    (/ nx, ny, (nz-1)*(coord+1) + 1 - nz_end /),                               &
    x(1:nx) , y(1:ny) , zw(1:(nz-nz_end) ),                                    &
    1, (/ 'VelocityZ' /), (/ tavg(1:nx,1:ny,1:nz- nz_end) % w /) )

call write_parallel_cgns(fname_vel2,nx,ny,nz- nz_end,nz_tot,                   &
    (/ 1, 1,   (nz-1)*coord + 1 /),                                            &
    (/ nx, ny, (nz-1)*(coord+1) + 1 - nz_end /),                               &
    x(1:nx) , y(1:ny) , zw(1:(nz-nz_end) ), 6,                                 &
    (/ 'Mean--uu', 'Mean--vv', 'Mean--ww','Mean--uw','Mean--vw','Mean--uv'/),  &
    (/ tavg(1:nx,1:ny,1:nz- nz_end) % u2,                                      &
       tavg(1:nx,1:ny,1:nz- nz_end) % v2,                                      &
       tavg(1:nx,1:ny,1:nz- nz_end) % w2,                                      &
       tavg(1:nx,1:ny,1:nz- nz_end) % uw,                                      &
       tavg(1:nx,1:ny,1:nz- nz_end) % vw,                                      &
       tavg(1:nx,1:ny,1:nz- nz_end) % uv /) )

call write_parallel_cgns(fname_tau,nx,ny,nz- nz_end,nz_tot,                    &
    (/ 1, 1,   (nz-1)*coord + 1 /),                                            &
    (/ nx, ny, (nz-1)*(coord+1) + 1 - nz_end /),                               &
    x(1:nx) , y(1:ny) , zw(1:(nz-nz_end) ), 6,                                 &
    (/ 'Tau--txx', 'Tau--txy', 'Tau--tyy','Tau--txz','Tau--tyz','Tau--tzz'/),  &
    (/ tavg(1:nx,1:ny,1:nz- nz_end) % txx,                                     &
       tavg(1:nx,1:ny,1:nz- nz_end) % txy,                                     &
       tavg(1:nx,1:ny,1:nz- nz_end) % tyy,                                     &
       tavg(1:nx,1:ny,1:nz- nz_end) % txz,                                     &
       tavg(1:nx,1:ny,1:nz- nz_end) % tyz,                                     &
       tavg(1:nx,1:ny,1:nz- nz_end) % tzz /) )

call write_parallel_cgns(fname_f,nx,ny,nz- nz_end,nz_tot,                      &
    (/ 1, 1,   (nz-1)*coord + 1 /),                                            &
    (/ nx, ny, (nz-1)*(coord+1) + 1 - nz_end /),                               &
    x(1:nx) , y(1:ny) , zw(1:(nz-nz_end) ), 3,                                 &
    (/ 'bodyForX', 'bodyForY', 'bodyForZ' /),                                  &
    (/ tavg(1:nx,1:ny,1:nz- nz_end) % fx,                                      &
       tavg(1:nx,1:ny,1:nz- nz_end) % fy,                                      &
       tavg(1:nx,1:ny,1:nz- nz_end) % fz /) )

#ifdef PPOUTPUT_EXTRA
call write_parallel_cgns(fname_cs,nx,ny,nz- nz_end,nz_tot,                     &
    (/ 1, 1,   (nz-1)*coord + 1 /),                                            &
    (/ nx, ny, (nz-1)*(coord+1) + 1 - nz_end /),                               &
    x(1:nx) , y(1:ny) , zw(1:(nz-nz_end) ), 1,                                 &
    (/ 'Cs_Coeff'/),  (/ tavg(1:nx,1:ny,1:nz- nz_end) % cs_opt2 /) )

call write_parallel_cgns(fname_sgs,nx,ny,nz- nz_end,nz_tot,                     &
    (/ 1, 1,   (nz-1)*coord + 1 /),                                            &
    (/ nx, ny, (nz-1)*(coord+1) + 1 - nz_end /),                               &
    x(1:nx) , y(1:ny) , zw(1:(nz-nz_end) ), 1,                                 &
    (/ 'SGS'/),  (/ tavg_sgs(1:nx,1:ny,1:nz- nz_end) % Nu_t /) )
#endif

#else
! Write binary data
open(unit=13, file=fname_vel, form='unformatted', convert=write_endian,        &
    access='direct', recl=nx*ny*nz*rprec)
write(13,rec=1) tavg(:nx,:ny,1:nz)%u
write(13,rec=2) tavg(:nx,:ny,1:nz)%v
write(13,rec=3) tavg(:nx,:ny,1:nz)%w_uv
close(13)

! Write binary data
open(unit=13, file=fname_velw, form='unformatted', convert=write_endian,       &
    access='direct', recl=nx*ny*nz*rprec)
write(13,rec=1) tavg(:nx,:ny,1:nz)%w
close(13)

open(unit=13, file=fname_vel2, form='unformatted', convert=write_endian,       &
    access='direct', recl=nx*ny*nz*rprec)
write(13,rec=1) tavg(:nx,:ny,1:nz)%u2
write(13,rec=2) tavg(:nx,:ny,1:nz)%v2
write(13,rec=3) tavg(:nx,:ny,1:nz)%w2
write(13,rec=4) tavg(:nx,:ny,1:nz)%uw
write(13,rec=5) tavg(:nx,:ny,1:nz)%vw
write(13,rec=6) tavg(:nx,:ny,1:nz)%uv
close(13)

open(unit=13, file=fname_tau, form='unformatted', convert=write_endian,        &
    access='direct', recl=nx*ny*nz*rprec)
write(13,rec=1) tavg(:nx,:ny,1:nz)%txx
write(13,rec=2) tavg(:nx,:ny,1:nz)%txy
write(13,rec=3) tavg(:nx,:ny,1:nz)%tyy
write(13,rec=4) tavg(:nx,:ny,1:nz)%txz
write(13,rec=5) tavg(:nx,:ny,1:nz)%tyz
write(13,rec=6) tavg(:nx,:ny,1:nz)%tzz
close(13)

open(unit=13, file=fname_f, form='unformatted', convert=write_endian,          &
    access='direct', recl=nx*ny*nz*rprec)
write(13,rec=1) tavg(:nx,:ny,1:nz)%fx
write(13,rec=2) tavg(:nx,:ny,1:nz)%fy
write(13,rec=3) tavg(:nx,:ny,1:nz)%fz
close(13)

!open(unit=13, file=fname_deriv, form='unformatted', convert=write_endian,         &
!    access='direct', recl=nx*ny*nz*rprec)
!write(13,rec=1) tavg(:nx,:ny,1:nz)%dudz
!write(13,rec=2) tavg(:nx,:ny,1:nz)%dvdz
!write(13,rec=3) tavg(:nx,:ny,1:nz)%dwdz
!write(13,rec=4) tavg(:nx,:ny,1:nz)%dwdz_w
!close(13)

#ifdef PPOUTPUT_EXTRA
open(unit=13, file=fname_cs, form='unformatted', convert=write_endian,         &
    access='direct', recl=nx*ny*nz*rprec)
write(13,rec=1) tavg(:nx,:ny,1:nz)%cs_opt2
close(13)

open(unit=13, file=fname_sgs, form='unformatted', convert=write_endian,         &
    access='direct', recl=nx*ny*nz*rprec)
write(13,rec=1) tavg_sgs(:nx,:ny,1:nz)%Nu_t
close(13)

call mpi_sync_real_array( tavg_sgs(1:nx,1:ny,lbz:nz)%Nu_t, 0, MPI_SYNC_DOWNUP )
#endif



#endif

#ifdef PPMPI
! Ensure all writes complete before preceeding
call mpi_barrier( comm, ierr )
#endif

! Do the Reynolds stress calculations afterwards. Now we can interpolate w and
! ww to the uv grid and do the calculations. We have already written the data to
! the files so we can overwrite now
rs = rs_compute(tavg , lbz)

! Calculate tke budget
!tke = tke_compute(tavg , rs, lbz)

#ifdef PPCGNS
! Write CGNS data
call write_parallel_cgns(fname_rs,nx,ny,nz- nz_end,nz_tot,                     &
    (/ 1, 1,   (nz-1)*coord + 1 /),                                            &
    (/ nx, ny, (nz-1)*(coord+1) + 1 - nz_end /),                               &
    x(1:nx) , y(1:ny) , z(1:(nz-nz_end) ), 6,                                  &
    (/ 'Meanupup', 'Meanvpvp', 'Meanwpwp','Meanupwp','Meanvpwp','Meanupvp'/),  &
    (/ rs(1:nx,1:ny,1:nz- nz_end) % up2,                                       &
    rs(1:nx,1:ny,1:nz- nz_end) % vp2,                                          &
    rs(1:nx,1:ny,1:nz- nz_end) % wp2,                                          &
    rs(1:nx,1:ny,1:nz- nz_end) % upwp,                                         &
    rs(1:nx,1:ny,1:nz- nz_end) % vpwp,                                         &
    rs(1:nx,1:ny,1:nz- nz_end) % upvp /) )
#else
! Write binary data
open(unit=13, file=fname_rs, form='unformatted', convert=write_endian,         &
    access='direct',recl=nx*ny*nz*rprec)
write(13,rec=1) rs(:nx,:ny,1:nz)%up2
write(13,rec=2) rs(:nx,:ny,1:nz)%vp2
write(13,rec=3) rs(:nx,:ny,1:nz)%wp2
write(13,rec=4) rs(:nx,:ny,1:nz)%upwp
write(13,rec=5) rs(:nx,:ny,1:nz)%vpwp
write(13,rec=6) rs(:nx,:ny,1:nz)%upvp
close(13)

!open(unit=13, file=fname_tke, form='unformatted', convert=write_endian,         &
!    access='direct',recl=nx*ny*nz*rprec)
!write(13,rec=1) tke(:nx,:ny,1:nz)%p
!close(13)

#endif

deallocate(rs)
!deallocate(tke)

#ifdef PPMPI
! Ensure all writes complete before preceeding
call mpi_barrier( comm, ierr )
#endif

end subroutine tavg_finalize

!*******************************************************************************
subroutine tavg_checkpoint()
!*******************************************************************************
!
! This subroutine writes the restart data and is to be called by 'checkpoint'
! for intermediate checkpoints and by 'tavg_finalize' at the end of the
! simulation.
!
use param, only : checkpoint_tavg_file, write_endian
use stat_defs, only : tavg_total_time, tavg
#ifdef PPOUTPUT_EXTRA
use param, only : checkpoint_tavg_sgs_file
use stat_defs, only : tavg_total_time_sgs, tavg_sgs
#endif
implicit none

character(64) :: fname

fname = checkpoint_tavg_file
#ifdef PPMPI
call string_concat( fname, '.c', coord)
#endif

!  Write data to tavg.out
open(1, file=fname, action='write', position='rewind',form='unformatted',      &
    convert=write_endian)
write(1) tavg_total_time
write(1) tavg
close(1)

#ifdef PPOUTPUT_EXTRA
fname = checkpoint_tavg_sgs_file
#ifdef PPMPI
call string_concat( fname, '.c', coord)
#endif
!  Write data to tavg_sgs.out
open(1, file=fname, action='write', position='rewind',form='unformatted',      &
    convert=write_endian)
write(1) tavg_total_time_sgs
write(1) tavg_sgs
close(1)
#endif

end subroutine tavg_checkpoint

!**********************************************************************************
end module io
