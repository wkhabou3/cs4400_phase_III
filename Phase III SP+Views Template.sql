
-- CS4400: Introduction to Database Systems: Monday, October 13, 2025
-- ER Management System Stored Procedures & Views Template [1]

/* This is a standard preamble for most of our scripts.  The intent is to establish
a consistent environment for the database behavior. */
set global transaction isolation level serializable;
set global SQL_MODE = 'ANSI,TRADITIONAL';
set session SQL_MODE = 'ANSI,TRADITIONAL';
set names utf8mb4;
set SQL_SAFE_UPDATES = 0;

set @thisDatabase = 'er_hospital_management';
use er_hospital_management;

-- -------------------
-- Views
-- -------------------

-- [1] room_wise_view()
-- -----------------------------------------------------------------------------
/* This view provides an overview of patient room assignments, including the patients’ 
first and last names, room numbers, managing department names, assigned doctors' first and 
last names (through appointments), and nurses' first and last names (through room). 
It displays key relationships between patients, their assigned medical staff, and 
the departments overseeing their care. Note that there will be a row for each combination 
of assigned doctor and assigned nurse.*/
-- -----------------------------------------------------------------------------
create or replace view room_wise_view as
select p.firstName as patient_fname, p.lastName as patient_lname, roomNumber, longName,
d.firstName as doctor_fname, d.lastName as doctor_lname,
n.firstName as nurse_fname, n.lastName as nurse_lname from patient p2
join person p on p2.ssn = p.ssn
join room on p.ssn = occupiedBy
left join department on managingDept = deptId
left join appt_assignment on p.ssn = patientId
left join doctor d2 on doctorId = d2.ssn
left join person d on d2.ssn = d.ssn
natural join room_assignment
left join nurse n2 on nurseId = n2.ssn
left join person n on n2.ssn = n.ssn;

-- [2] symptoms_overview_view()
-- -----------------------------------------------------------------------------
/* This view provides a comprehensive overview of patient appointments
along with recorded symptoms. Each row displays the patient’s SSN, their full name 
(HINT: the CONCAT function can be useful here), the appointment time, appointment date, 
and a list of symptoms recorded during the appointment with each symptom separated by a 
comma and a space (HINT: the GROUP_CONCAT function can be useful here). */
-- -----------------------------------------------------------------------------
create or replace view symptoms_overview_view as
select p.ssn, concat(p.firstName, ' ', p.lastName) as fullName, a.apptDate, a.apptTime, group_concat(symptomType separator ', ') as symptoms from patient p2
join person p on p2.ssn = p.ssn
join appointment a on p.ssn = patientId
join symptom s on (a.patientId, a.apptDate, a.apptTime) = (s.patientId, s.apptDate, s.apptTime)
group by p.ssn, a.apptTime, a.apptDate;

-- [3] medical_staff_view()
-- -----------------------------------------------------------------------------
/* This view displays information about medical staff. For every nurse and doctor, it displays
their ssn, their "staffType" being either "nurse" or "doctor", their "licenseInfo" being either
their licenseNumber or regExpiration, their "jobInfo" being either their shiftType or 
experience, a list of all departments they work in in alphabetical order separated by a
comma and a space (HINT: the GROUP_CONCAT function can be useful here), and their "numAssignments" 
being either the number of rooms they're assigned to or the number of appointments they're assigned to. */
-- -----------------------------------------------------------------------------
create or replace view medical_staff_view as
select ssn, 'nurse' as staffType, regExpiration as licenseInfo, shiftType as jobInfo,
group_concat(distinct longName order by longName separator ', ') as departments, count(roomNumber) as numAssignments from nurse
join works_in on ssn = staffSsn
natural join department
join room_assignment on ssn = nurseId
group by ssn
union
select ssn, 'doctor' as staffType, licenseNumber as licenseInfo, experience as jobInfo,
group_concat(distinct longName order by longName separator ', ') as departments, count(apptDate) as numAssignments from doctor
join works_in on ssn = staffSsn
natural join department
join appt_assignment on ssn = doctorId
group by ssn;

-- [4] department_view()
-- -----------------------------------------------------------------------------
/* This view displays information about every department in the hospital. The information
displayed should be the department's long name, number of total staff members, the number of 
doctors in the department, and the number of nurses in the department. If a department does not 
have any doctors/nurses/staff members, ensure the output for those columns is zero, not null */
-- -----------------------------------------------------------------------------

create or replace view department_view as
select longName, count(s.ssn) as staff_count, count(d.ssn) as doctor_count, count(n.ssn) as nurse_count from department
natural left join works_in
left join staff s on staffSsn = s.ssn
left join doctor d on staffSsn = d.ssn
left join nurse n on staffSsn = n.ssn
group by longName;

-- [5] outstanding_charges_view()
-- -----------------------------------------------------------------------------
/* This view displays the outstanding charges for the patients in the hospital. 
“Outstanding charges” is the sum of appointment costs and order costs. It also 
displays a patient’s first name, last name, SSN, funds, number of appointments, 
and number of orders. Ensure there are no null values if there are no charges, 
appointments, orders for a patient (HINT: the IFNULL or COALESCE functions can be 
useful here).  */
-- -----------------------------------------------------------------------------
create or replace view outstanding_charges_view as
select p.firstName, lastName, p.ssn, funds, 
coalesce((select sum(cost) from appointment where patientId = p.ssn) 
+ (select sum(cost) from med_order where patientId = p.ssn), 
sum(a.cost), sum(o.cost), 0) as outstanding_charges,
count(distinct apptDate, apptTime) as appt_count, count(orderNumber) as order_count from patient
natural join person p
left join appointment a on ssn = a.patientId
left join med_order o on ssn = o.patientId
group by ssn;

-- -------------------
-- Stored Procedures
-- -------------------

-- [6] add_patient()
-- -----------------------------------------------------------------------------
/* This stored procedure creates a new patient. If the new patient does 
not exist in the person table, then add them prior to adding the patient. 
Ensure that all input parameters are non-null, and that a patient with the given 
SSN does not already exist. */
-- -----------------------------------------------------------------------------
drop procedure if exists add_patient;
delimiter /​/
create procedure add_patient (
	in ip_ssn varchar(40),
    in ip_first_name varchar(100),
    in ip_last_name varchar(100),
    in ip_birthdate date,
    in ip_address varchar(200), 
    in ip_funds integer,
    in ip_contact char(12)
)
sp_main: begin
	-- Check: Args are not null, ssn not already in patient table
	if (ip_ssn is not null and ip_first_name is not null
    and ip_last_name is not null and ip_birthdate is not null
    and ip_address is not null and ip_funds is not null
    and ip_contact is not null) and (ip_ssn not in (select ssn from patient))
    then
		-- If ssn not in person table, insert into person first
		if ip_ssn not in (select ssn from person)
        then
			insert into person (ssn, firstName, lastName, birthdate, address) values
			(ip_ssn, ip_first_name, ip_last_name, ip_birthdate, ip_address);
		end if;
		insert into patient (ssn, funds, contact) values
		(ip_ssn, ip_funds, ip_contact);
	end if;
end /​/
delimiter ;

-- [7] record_symptom()
-- -----------------------------------------------------------------------------
/* This stored procedure records a new symptom for a patient. Ensure that all input 
parameters are non-null, and that the referenced appointment exists for the given 
patient, date, and time. Ensure that the same symptom is not already recorded for 
that exact appointment. */
-- -----------------------------------------------------------------------------
drop procedure if exists record_symptom;
delimiter /​/
create procedure record_symptom (
	in ip_patientId varchar(40),
    in ip_numDays int,
    in ip_apptDate date,
    in ip_apptTime time,
    in ip_symptomType varchar(100)
)
sp_main: begin
	-- code here
	if ip_patientId is null or ip_numDays is null or ip_apptDate is null or ip_apptTime is null or 
    ip_symptomType is null then leave sp_main;
    end if;
    update symptom set symptomType = ip_symptomType where patientId = ip_patientId and apptDate = ip_apptDate
    and apptTime = ip_apptTime and (symptomType is null or symptomType != ip_symptomType);
end /​/
delimiter ;

-- [8] book_appointment()
-- -----------------------------------------------------------------------------
/* This stored procedure books a new appointment for a patient at a specific time and date.
The appointment date/time must be in the future (the CURDATE() and CURTIME() functions will
be helpful). The patient must not have any conflicting appointments and must have the funds
to book it on top of any outstanding costs. Each call to this stored procedure must add the 
relevant data to the appointment table if conditions are met. Ensure that all input parameters 
are non-null and reference an existing patient, and that the cost provided is non‑negative. 
Do not charge the patient, but ensure that they have enough funds to cover their current outstanding 
charges and the cost of this appointment.
HINT: You should complete outstanding_charges_view before this procedure! */
-- -----------------------------------------------------------------------------
drop procedure if exists book_appointment;
delimiter /​/
create procedure book_appointment (
	in ip_patientId char(11),
	in ip_apptDate date,
    in ip_apptTime time,
	in ip_apptCost integer
)
sp_main: begin
	if ip_patientId is not null and ip_apptDate is not null and ip_apptTime is not null and ip_apptCost is not null and ip_apptCost >= 0
    and (ip_apptDate > CURDATE() or (ip_apptDate = CURDATE() and ip_apptTime > CURTIME()))
    and exists (select 1 from patient where ssn = ip_patientId)
    and not exists (select 1 from appointment where patientId = ip_patientId and apptDate = ip_apptDate and apptTime = ip_apptTime)
    and (select funds from patient where ssn = ip_patientId) >= ip_apptCost + (select outstanding_charges from outstanding_charges_view where ssn = ip_patientId) then
		insert into appointment values (ip_patientId, ip_apptDate, ip_apptTime, ip_apptCost);
    end if;
end /​/
delimiter ;

-- [9] place_order()
-- -----------------------------------------------------------------------------
/* This stored procedures places a new order for a patient as ordered by their
doctor. The patient must also have enough funds to cover the cost of the order on 
top of any outstanding costs. Each call to this stored procedure will represent 
either a prescription or a lab report, and the relevant data should be added to the 
corresponding table. Ensure that the order-specific, patient-specific, and doctor-specific 
input parameters are non-null, and that either all the labwork specific input parameters are 
non-null OR all the prescription-specific input parameters are non-null (i.e. if ip_labType 
is non-null, ip_drug and ip_dosage should both be null).
Ensure the inputs reference an existing patient and doctor. 
Ensure that the order number is unique for all orders and positive. Ensure that a cost 
is provided and non‑negative. Do not charge the patient, but ensure that they have 
enough funds to cover their current outstanding charges and the cost of this appointment. 
Ensure that the priority is within the valid range. If the order is a prescription, ensure 
the dosage is positive. Ensure that the order is never recorded as both a lab work and a prescription.
The order date inserted should be the current date, and the previous procedure lists a function that
will be required to use in this procedure as well.
HINT: You should complete outstanding_charges_view before this procedure! */
-- -----------------------------------------------------------------------------
drop procedure if exists place_order;
delimiter /​/
create procedure place_order (
	in ip_orderNumber int, 
	in ip_priority int,
    in ip_patientId char(11), 
	in ip_doctorId char(11),
    in ip_cost integer,
    in ip_labType varchar(100),
    in ip_drug varchar(100),
    in ip_dosage int
)
sp_main: begin
	-- Check: Args not null; patientId and doctorId exist; orderNumber unique; orderNumber positive; cost nonnegative; cost + outstanding charge < funds; priority between 1 and 5
	if ip_orderNumber is not null and ip_priority is not null
    and ip_patientId is not null and ip_doctorId is not null
    and ip_cost is not null and ip_patientId in (select ssn from patient)
    and ip_doctorId in (select ssn from doctor) and ip_orderNumber > 0 
    and ip_orderNumber not in (select orderNumber from med_order)
    and ip_cost >= 0
    and ip_cost + (select outstanding_charges from outstanding_charges_view where ssn = ip_patientId) < (select funds from patient where ssn = ip_patientId)
    and ip_priority >= 1 and ip_priority <= 5
    then
		-- Check if order is a lab_work. Insert into order and lab_work
		if ip_labType is not null and
        ip_drug is null and ip_dosage is null
        then
			insert into med_order (orderNumber, orderDate, priority, patientId, doctorId, cost) values
            (ip_orderNumber, curdate(), ip_priority, ip_patientId, ip_doctorId, ip_cost);
            insert into lab_work (orderNumber, labType) values
            (ip_orderNumber, ip_labType);
        end if;
        
        -- Check if orrder is a prescription, and that the dosage is positive. Inssert into order and prescription
        if ip_labType is null and
        ip_drug is not null and ip_dosage is not null
        and ip_dosage > 0
        then
			insert into med_order (orderNumber, orderDate, priority, patientId, doctorId, cost) values
            (ip_orderNumber, curdate(), ip_priority, ip_patientId, ip_doctorId, ip_cost);
            insert into prescription (orderNumber, drug, dosage) values
            (ip_orderNumber, ip_drug, ip_dosage);
        end if;
    end if;
end /​/
delimiter ;

-- [10] add_staff_to_dept()
-- -----------------------------------------------------------------------------
/* This stored procedure adds a staff member to a department. If they are already
a staff member and not a manager for a different department, they can be assigned
to this new department. If they are not yet a staff member or person, they can be 
assigned to this new department and all other necessary information should be 
added to the database. Ensure that all input parameters are non-null and that the 
Department ID references an existing department. Ensure that the staff member is 
not already assigned to the department. */
-- -----------------------------------------------------------------------------
drop procedure if exists add_staff_to_dept;
delimiter /​/
create procedure add_staff_to_dept (
	in ip_deptId integer,
    in ip_ssn char(11),
    in ip_firstName varchar(100),
	in ip_lastName varchar(100),
    in ip_birthdate date,
    in ip_startdate date,
    in ip_address varchar(200),
    in ip_staffId integer,
    in ip_salary integer
)
sp_main: begin
	-- code here
	    -- check if null
    if ip_deptId is null or ip_ssn is null or ip_firstName is null or ip_lastName is null or ip_birthdate is null
    or ip_startdate is null or ip_address is null or ip_staffId is null or ip_salary is null then leave sp_main;
    end if;
    -- check for valid dept
    if not exists (select 1 from works_in where deptId = ip_deptId) then leave sp_main; end if;
    
    -- if emp not exists we need to add to tables (need to check is not in person)
    if not exists (select 1 from staff where ssn = ip_ssn) then 
    insert into person(ssn, firstName, lastName, birthdate, address) 
    values(ip_ssn, ip_firstName, ip_lastName, ip_birthdate, ip_address);
    insert into staff(ssn, staffId, hireDate, salary) values (ip_ssn, ip_staffId, ip_startdate, ip_salary);
    insert into works_in(staffSsn, deptId) values (ip_ssn, ip_deptId);
    leave sp_main; end if;
    
    -- if emp in works_in we update the table entry
    if exists (select 1 from works_in where staffSsn = ip_ssn) then
    update works_in set deptId = ip_deptId where staffSsn = ip_ssn; end if;
end /​/
delimiter ;

-- [11] add_funds()
-- -----------------------------------------------------------------------------
/* This stored procedure adds funds to an existing patient. The amount of funds
added must be positive. Ensure that all input parameters are non-null and reference 
an existing patient. */
-- -----------------------------------------------------------------------------
drop procedure if exists add_funds;
delimiter /​/
create procedure add_funds (
	in ip_ssn char(11),
    in ip_funds integer
)
sp_main: begin
	if ip_ssn is not null and ip_funds is not null and ip_funds > 0 and ip_ssn in (select ssn from patient) then
        update patient set funds = funds + ip_funds where ssn = ip_ssn;
	end if;
end /​/
delimiter ;

-- [12] assign_nurse_to_room()
-- -----------------------------------------------------------------------------
/* This stored procedure assigns a nurse to a room. In order to ensure they
are not over-booked, a nurse cannot be assigned to more than 4 rooms. Ensure that 
all input parameters are non-null and reference an existing nurse and room. */
-- -----------------------------------------------------------------------------
drop procedure if exists assign_nurse_to_room;
delimiter /​/
create procedure assign_nurse_to_room (
	in ip_nurseId char(11),
    in ip_roomNumber integer
)
sp_main: begin
	-- Check: no args are null, nurseId and roomNumber exist, assignment doesn't already exist, less than three assignments for nurse
	if ip_nurseId is not null and ip_roomNumber is not null
    and ip_nurseId in (select ssn from nurse)
    and ip_roomNumber in (select roomNumber from room)
    and (ip_nurseId, ip_roomNumber) not in (select nurseId, roomNumber from room_assignment)
    and ((select count(nurseId) from room_assignment where nurseId = ip_nurseId group by nurseId) < 4
    or ip_nurseId not in (select nurseId from room_assignment))
    then
		insert into room_assignment (nurseId, roomNumber) values
        (ip_nurseId, ip_roomNumber);
    end if;
end /​/
delimiter ;
-- Test: nurse not assigned to any rooms,

-- [13] assign_room_to_patient()
-- -----------------------------------------------------------------------------
/* This stored procedure assigns a room to a patient. The room must currently be
unoccupied. If the patient is currently assigned to a different room, they should 
be removed from that room. To ensure that the patient is placed in the correct type 
of room, we must also confirm that the provided room type matches that of the 
provided room number. Ensure that all input parameters are non-null and reference 
an existing patient and room. */
-- -----------------------------------------------------------------------------
drop procedure if exists assign_room_to_patient;
delimiter /​/
create procedure assign_room_to_patient (
    in ip_ssn char(11),
    in ip_roomNumber int,
    in ip_roomType varchar(100)
)
sp_main: begin
    -- code here
	if ip_ssn is null or ip_roomNumber is null or ip_roomType is null then leave sp_main; end if;
    -- loop thru rows with occupiedBy = ip_ssn and delete occupiedBy/set to null
    -- then find room where roomNumber = ip_roomNumber and ip_roomType = roomType and set occupiedBy = ip_ssn
    update room set occupiedBy = null where occupiedBy = ip_ssn;
    update room set occupiedBy = ip_ssn where roomType = ip_roomType and occupiedBy is null;
end /​/
delimiter ;

-- [14] assign_doctor_to_appointment()
-- -----------------------------------------------------------------------------
/* This stored procedure assigns a doctor to an existing appointment. Ensure that no
more than 3 doctors are assigned to an appointment, and that the doctor does not
have commitments to other patients at the exact appointment time. Ensure that all input 
parameters are non-null and reference an existing doctor and appointment. */
-- -----------------------------------------------------------------------------
drop procedure if exists assign_doctor_to_appointment;
delimiter /​/
create procedure assign_doctor_to_appointment (
	in ip_patientId char(11),
    in ip_apptDate date,
    in ip_apptTime time,
    in ip_doctorId char(11)
)
sp_main: begin
	if ip_patientId is not null and ip_apptDate is not null and ip_apptTime is not null and ip_doctorId is not null
    and exists (select 1 from appointment where patientId = ip_patientId and apptDate = ip_apptDate and apptTime = ip_apptTime)
    and exists (select 1 from doctor where ssn = ip_doctorId)
    and (select count(*) from appt_assignment where patientId = ip_patientId and apptDate = ip_apptDate and apptTime = ip_apptTime) < 3
    and not exists (select 1 from appt_assignment where doctorId = ip_doctorId and apptDate = ip_apptDate and apptTime = ip_apptTime) then
		insert into appt_assignment values (ip_patientId, ip_apptDate, ip_apptTime, ip_doctorId);
	end if;
end /​/
delimiter ;

-- [15] manage_department()
-- -----------------------------------------------------------------------------
/* This stored procedure assigns a staff member as the manager of a department.
The staff member cannot currently be the manager for any departments. They
should be removed from working in any departments except the given
department (make sure the staff member is not the sole employee for any of these 
other departments, as they cannot leave and be a manager for another department otherwise),
for which they should be set as its manager. Ensure that all input parameters are non-null 
and reference an existing staff member and department.
*/
-- -----------------------------------------------------------------------------
drop procedure if exists manage_department;
delimiter /​/
create procedure manage_department (
	in ip_ssn char(11),
    in ip_deptId int
)
sp_main: begin
-- Check: args are not null, ssn and department exist, ssn is not a manager, ssn does not work in any departments as the sole employee
	if ip_ssn is not null and ip_deptId is not null
    and ip_ssn in (select ssn from staff)
    and ip_deptId in (select deptId from department)
    and ip_ssn not in (select manager from department)
    and ip_ssn not in (select staffSsn from works_in natural join department where longName in
    (select longName from department_view where staff_count = 1) and deptId != ip_deptId)
    then
		-- Delete ssn from all departments
		delete from works_in where staffSsn = ip_ssn;
        -- Reinstate ssn into input department and set them to manager of dept
        insert into works_in (staffSsn, deptId) values
        (ip_ssn, ip_deptId);
        update department set manager = ip_ssn where deptId = ip_deptId;
    end if;
end /​/
delimiter ;
-- Test: ssn works as sole employee of any dept, ssn set as manager but not in works_in table (is this even possible)

-- [16] release_room()
-- -----------------------------------------------------------------------------
/* This stored procedure removes a patient from a given room. Ensure that 
the input room number is non-null and references an existing room.  */
-- -----------------------------------------------------------------------------
drop procedure if exists release_room;
delimiter /​/
create procedure release_room (
    in ip_roomNumber int
)
sp_main: begin
	-- code here
	 if ip_roomNumber is null then leave sp_main; end if;
    update room set occupiedBy = null where roomNumber = ip_roomNumber;
end /​/
delimiter ;

-- [17] remove_patient()
-- -----------------------------------------------------------------------------
/* This stored procedure removes a given patient. If the patient has any pending
orders or remaining appointments (regardless of time), they cannot be removed.
If the patient is not a staff member, they then must be completely removed from 
the database. Ensure all data relevant to this patient is removed. Ensure that the 
input SSN is non-null and references an existing patient. */
-- -----------------------------------------------------------------------------
drop procedure if exists remove_patient;
delimiter /​/
create procedure remove_patient (
	in ip_ssn char(11)
)
sp_main: begin
	if ip_ssn is not null
    and exists (select 1 from patient where ssn = ip_ssn)
    and not exists (select 1 from appointment where patientId = ip_ssn)
    and not exists (select 1 from med_order where patientId = ip_ssn) then
		delete from patient where ssn = ip_ssn;
        if not exists (select 1 from staff where ssn = ip_ssn) then
			delete from person where ssn = ip_ssn;
        end if;
        update room set occupiedBy = null where occupiedBy = ip_ssn;
    end if;
end /​/
delimiter ;

-- remove_staff()
-- Lucky you, we provided this stored procedure to you because it was more complex
-- than we would expect you to implement. You will need to call this procedure
-- in the next procedure!
-- -----------------------------------------------------------------------------
/* This stored procedure removes a given staff member. If the staff member is a 
manager, they are not removed. If the staff member is a nurse, all rooms
they are assigned to have a remaining nurse if they are to be removed. 
If the staff member is a doctor, all appointments they are assigned to have
a remaining doctor and they have no pending orders if they are to be removed.
If the staff member is not a patient, then they are completely removed from 
the database. All data relevant to this staff member is removed. */
-- -----------------------------------------------------------------------------
drop procedure if exists remove_staff;
delimiter /​/
create procedure remove_staff (
	in ip_ssn char(11)
)
sp_main: begin
	-- ensure parameters are not null
    if ip_ssn is null then
		leave sp_main;
	end if;
    
	-- ensure staff member exists
	if not exists (select ssn from staff where ssn = ip_ssn) then
		leave sp_main;
	end if;
	
    -- if staff member is a nurse
    if exists (select ssn from nurse where ssn = ip_ssn) then
	if exists (
		select 1
		from (
			 -- Get all rooms assigned to the nurse
			 select roomNumber
			 from room_assignment
			 where nurseId = ip_ssn
		) as my_rooms
		where not exists (
			 -- Check if there is any other nurse assigned to that room
			 select 1
			 from room_assignment 
			 where roomNumber = my_rooms.roomNumber
			   and nurseId <> ip_ssn
		)
	)
	then
		leave sp_main;
	end if;
		
        -- remove this nurse from room_assignment and nurse tables
		delete from room_assignment where nurseId = ip_ssn;
		delete from nurse where ssn = ip_ssn;
	end if;
	
    -- if staff member is a doctor
	if exists (select ssn from doctor where ssn = ip_ssn) then
		-- ensure the doctor does not have any pending orders
		if exists (select * from med_order where doctorId = ip_ssn) then 
			leave sp_main;
		end if;
		
		-- ensure all appointments assigned to this doctor have remaining doctors assigned
		if exists (
		select 1
		from (
			 -- Get all appointments assigned to ip_ssn
			 select patientId, apptDate, apptTime
			 from appt_assignment
			 where doctorId = ip_ssn
		) as ip_appointments
		where not exists (
			 -- For the same appointment, check if there is any other doctor assigned
			 select 1
			 from appt_assignment 
			 where patientId = ip_appointments.patientId
			   and apptDate = ip_appointments.apptDate
			   and apptTime = ip_appointments.apptTime
			   and doctorId <> ip_ssn
		)
	)
	then
		leave sp_main;
	end if;
        
		-- remove this doctor from appt_assignment and doctor tables
		delete from appt_assignment where doctorId = ip_ssn;
		delete from doctor where ssn = ip_ssn;
	end if;
    
    -- remove staff member from works_in and staff tables
    delete from works_in where staffSsn = ip_ssn;
    delete from staff where ssn = ip_ssn;

	-- ensure staff member is not a patient
	if exists (select * from patient where ssn = ip_ssn) then 
		leave sp_main;
	end if;
    
    -- remove staff member from person table
	delete from person where ssn = ip_ssn;
end /​/
delimiter ;

-- [18] remove_staff_from_dept()
-- -----------------------------------------------------------------------------
/* This stored procedure removes a staff member from a department. If the staff
member is the manager of that department, they cannot be removed. If the staff
member, after removal, is no longer working for any departments, they should then 
also be removed as a staff member, following all logic in the remove_staff procedure. 
Ensure that all input parameters are non-null and that the given person works for
the given department. Ensure that the department will have at least one staff member 
remaining after this staff member is removed. */
-- -----------------------------------------------------------------------------
drop procedure if exists remove_staff_from_dept;
delimiter /​/
create procedure remove_staff_from_dept (
	in ip_ssn char(11),
    in ip_deptId integer
)
sp_main: begin
	-- Check: No args are null, ssn and deptId exist, employee works in dept, ssn not manager of this dept, dept has more than 1 employee
	if ip_ssn is not null and ip_deptId is not null
    and ip_ssn in (select ssn from staff)
    and ip_deptId in (select deptId from department)
    and (ip_ssn, ip_deptId) in (select staffSsn, deptId from works_in)
    and ip_ssn not in (select manager from department where deptId = ip_deptId)
    and (select staff_count from department_view natural join department where deptId = ip_deptId) > 1
    then
		-- Remove staff/dept relationship from works_in
		delete from works_in where staffSsn = ip_ssn and deptId = ip_deptId;
        -- If staff no longer working for any departments, then call remove_staff
        if ip_ssn not in (select staffSsn from works_in)
        then
			call remove_staff(ip_ssn);
        end if;
    end if;
end /​/
delimiter ;

-- [19] complete_appointment()
-- -----------------------------------------------------------------------------
/* This stored procedure completes an appointment given its date, time, and patient SSN.
The completed appointment and any related information should be removed 
from the system, and the patient should be charged accordingly. Ensure that all 
input parameters are non-null and that they reference an existing appointment. */
-- -----------------------------------------------------------------------------
drop procedure if exists complete_appointment;
delimiter /​/
create procedure complete_appointment (
	in ip_patientId char(11),
    in ip_apptDate DATE, 
    in ip_apptTime TIME
)
sp_main: begin
	-- code here
	if ip_patientId is null or ip_apptDate is null or ip_apptTime is null then leave sp_main; end if;
    update patient set funds= funds-cost where patientId = ip_patientId;
    delete from appointment where patientId = ip_patientId and ip_apptDate = apptDate and ip_apptTime = apptTime;
    
end /​/
delimiter ;

-- [20] complete_orders()
-- -----------------------------------------------------------------------------
/* This stored procedure attempts to complete a certain number of orders based on the 
passed in value. Orders should be completed in order of their priority, from highest to
lowest. If multiple orders have the same priority, the older dated one should be 
completed first. Any completed orders should be removed from the system, and patients 
should be charged accordingly. Ensure that there is a non-null number of orders
passed in, and complete as many as possible up to that limit. */
-- -----------------------------------------------------------------------------
drop procedure if exists complete_orders;
delimiter /​/
create procedure complete_orders (
	in ip_num_orders integer
)
sp_main: begin
	declare counter int default 0;
    declare orderNum int;
    declare orderCost int;
    declare orderPssn char(11);
	if ip_num_orders is null or ip_num_orders <= 0 then leave sp_main; end if;
    repeat
		select orderNumber, cost, patientId into orderNum, orderCost, orderPssn from med_order order by priority desc, orderDate asc limit 1;
        if orderNum is null then leave sp_main; end if;
        update patient set funds = funds - orderCost where ssn = orderPssn;
        delete from med_order where orderNumber = orderNum;
        set counter = counter + 1;
	until counter >= ip_num_orders
    end repeat;
end /​/
delimiter ;
