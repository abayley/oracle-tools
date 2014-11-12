whenever sqlerror exit rollback
-- http://stackoverflow.com/questions/1439203/favorite-sqlplus-tips-and-tricks
-- http://www.orafaq.com/wiki/SQL*Plus_FAQ
-- http://www.toadworld.com/platforms/oracle/w/wiki/3963.sql-plus.aspx
set feedback off termout on tab off wrap off trimout on trimspool on flush on appinfo on define on verify off long 1000000000 longc 1000000000
alter session set NLS_DATE_FORMAT = 'YYYY-MM-DD HH24:MI:SS';
alter session set NLS_TIMESTAMP_TZ_FORMAT = 'YYYY-MM-DD HH24:MI:SS.FF TZH:TZM';
alter session set NLS_TIMESTAMP_FORMAT = 'YYYY-MM-DD HH24:MI:SS.FF';
alter session set plsql_warnings='ENABLE:ALL';
set linesize 32767 pagesize 50000 heading on headsep off underline off space 2 serveroutput on size unlimited format wrapped feedback on

set heading off feedback off
column login format a100
select 'Login: ' || user || '@' || sys_context('userenv', 'db_name') as login from dual;
set heading on  feedback on
