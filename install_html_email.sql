whenever sqlerror exit failure
set serveroutput on
set define on
define use_app_log="FALSE"
define use_app_parameter="FALSE"
define use_mime_type="FALSE"
define use_invoker_rights="TRUE"
ALTER SESSION SET PLSQL_CCFLAGS='use_app_log:&&use_app_log.,use_app_parameter:&&use_app_parameter.,use_mime_type:&&use_mime_type.,use_invoker_rights:&&use_invoker_rights.';
-- set these appropriately for html_email_udt
define from_email_addr="donotreply@bogus.com"
define reply_to="donotreply@bogus.com"
define smtp_server="localhost"
--
-- if you do not want to install arr_varchar2_udt, then
-- change this to your own implementation of a type that consists of TABLE OF VARCHAR2(4000)
define array_varchar2_type="arr_varchar2_udt"
--
define subdir=.
-- Personal preference. comment these out if your DBA complains or
-- if you have an issue with the limits for amount of native code
ALTER SESSION SET plsql_code_type = NATIVE;
ALTER SESSION SET plsql_optimize_level=3;
BEGIN
$if $$use_app_parameter $then
    DBMS_OUTPUT.put_line('use_app_parameter is TRUE');
$else
    DBMS_OUTPUT.put_line('use_app_parameter is FALSE');
$end
$if $$use_app_log $then
    DBMS_OUTPUT.put_line('use_app_log is TRUE');
$else
    DBMS_OUTPUT.put_line('use_app_log is FALSE');
$end
$if $$use_mime_type $then
    DBMS_OUTPUT.put_line('use_mime_type is TRUE');
$else
    DBMS_OUTPUT.put_line('use_mime_type is FALSE');
$end
$if $$use_invoker_rights $then
    DBMS_OUTPUT.put_line('use_invoker_rights is TRUE');
$else
    DBMS_OUTPUT.put_line('use_invoker_rights is FALSE');
$end
END;
/
/*
    NOTE: you must have priv to write to the network. This is a big subject. 
    Here is what I did as sysdba in order for my account (lee) to be able to
    write to port 25 on the RedHat Linux server my Oracle database runs upon. 
    Assuming you have an smtp server somewhere other than your database server 
    like most sane organizations, you will need the ACL entry for that host 
    and the schema where you are deploying this. If not you will get:

        ORA-24247: network access denied by access control list (ACL)
    
    when you try to send an email. This is true even though we are writing 
    to localhost!

    port 25 was open in my RHL firewalld for outgoing. YMMV.

begin
    dbms_network_acl_admin.append_host_ace(
        host => 'localhost'
        ,lower_port => NULL
        ,upper_port => NULL
        ,ace => xs$ace_type(
            privilege_list => xs$name_list('smtp')
            ,principal_name => 'lee'
            ,principal_type => xs_acl.ptype_db
        )
    );
end;
<-- the slash goes here but sqlplus eats it and pukes even inside comment
*/
whenever sqlerror continue
-- the attachment type has a dependency
DROP TYPE html_email_udt;
prompt ok if type drop failed for not exists
DROP TYPE arr_email_attachment_udt;
prompt ok if type drop failed for not exists
whenever sqlerror exit failure
--
prompt Beginning anonymous block for mime_type_pkg
prompt will not deploy unless compile directive use_mime_type=TRUE
@&&subdir/mime_type.pks
prompt Beginning anonymous block for mime_type_pkg body
prompt will not deploy unless compile directive use_mime_type=TRUE
@&&subdir/mime_type.pkb
--
--
prompt create email_attachment_udt
@&&subdir/email_attachment_udt.tps
prompt create body email_attachment_udt
@&&subdir/email_attachment_udt.tpb
prompt create arr_email_attachment_udt
@&&subdir/arr_email_attachment_udt.tps
--
-- oh my, how embarrasing for Oracle. You cannot use compile directives in the
-- definition of a user defined type object. You can use them just fine in the
-- body, but not in creating the type itself (type specification). We will use 
-- the compile directives to create a character string that we feed to execute
-- immediate. Such a damn hack. Shame Oracle! Shame!
-- At least the hack is only for deployment code. I can live with it.
--
prompt begin anonymous block create html_email_udt spec
@&&subdir/html_email_udt.tps
prompt create html_email_udt body
@&&subdir/html_email_udt.tpb
-- reset these so do not cause session to be in state not chosen
ALTER SESSION SET plsql_optimize_level=2;
ALTER SESSION SET plsql_code_type = INTERPRETED;
--GRANT EXECUTE ON html_email_udt TO ???;
prompt deployment of html_email_udt and supporting types and packages is complete
