# html_email

Oracle PL/SQL E-mail Construction and Transmission with HTML Format Message Body and Optional Attachments

## Content
* [Installation](#installation)
* [html_email_udt](#html_email_udt)
    * [Example](#example)
    * [Sample Output](#sample-output)
    * [Mime Types](#mime-types)
    * [Type Specification](#type-specification)
    * [Privileges](#privileges)
    * [Method Chaining](#example)
* [install.sql](#installsql)

## Installation

Clone this repository or download it as a zip archive.

Note: [plsql_utilties](https://github.com/lee-lindley/plsql_utilities) is provided as a submodule,
so use the clone command with recursive-submodules option:

`git clone --recursive-submodules https://github.com/lee-lindley/html_email.git`

or download it separately as a zip archive and extract the content of root folder
into *plsql_utilities* folder.

Follow the instructions in [install.sql](#installsql)

Note that you do not absolutely require the submodule. The only essential
element is *arr_varchar2_udt* which is simple enough to create yourself
as noted in [install.sql](#installsql).

## html_email_udt

An Oracle Object Type for constructing and sending an HTML email, optionally with
attachments. The best way to explain is with a usage example.

### Example

This example is recorded as a comment in the type specification, modified
slightly here using my test case values:

```sql
DECLARE
    v_email         html_email_udt;
    v_src           SYS_REFCURSOR;
    v_query         VARCHAR2(32767) := q'!SELECT --+ no_parallel
            v.view_name AS "View Name"
            ,c.comments AS "Comments"
        FROM dictionary d
        INNER JOIN all_views v
            ON v.view_name = d.table_name
        LEFT OUTER JOIN all_tab_comments c
            ON c.table_name = v.view_name
        WHERE d.table_name LIKE 'ALL%'
        ORDER BY v.view_name
        FETCH FIRST 40 ROWS ONLY!';
    --
    -- Because you cannot CLOSE/ReOPEN a dynamic sys_refcursor variable directly,
    -- you must regenerate it and assign it. Weird restriction, but do not
    -- try to fight it by opening it in the main code twice. Get a fresh copy from a function.
    FUNCTION l_getcurs RETURN SYS_REFCURSOR IS
        l_src       SYS_REFCURSOR;
    BEGIN
        OPEN l_src FOR v_query;
        RETURN l_src;
    END;
BEGIN
    v_email := html_email_udt(
        p_to_list           => 'lee@linux2.localdomain, root@linux2.localdomain'
        ,p_from_email_addr  => 'nobody@linux2.localdomain'
        ,p_reply_to         => 'nobody@linux2.localdomain'
        ,p_subject          => 'A sample email from html_email_udt'
        ,p_smtp_server      => 'localhost'
    );
    v_email.add_paragraph('We constructed and sent this email with html_email_udt.');
    v_src := l_getcurs;

    -- convert sql query result set into HTML table
    v_email.add_table_to_body(p_refcursor => v_src, p_caption => 'DBA Views');

    -- need to close it because we are going to open again.
    -- The called package may have closed it, but must be sure or nasty
    -- bugs/caching can happen.
    BEGIN
        CLOSE v_src;
    EXCEPTION WHEN invalid_cursor THEN NULL;
    END;

    -- add a spreadsheet attachment
    -- https://github.com/mbleron/ExcelGen
    DECLARE
        l_xlsx_blob     BLOB;
        l_ctxId         ExcelGen.ctxHandle;
        l_sheet_handle  BINARY_INTEGER;
    BEGIN
        v_src := l_getcurs;
        l_ctxId := ExcelGen.createContext();
        l_sheet_handle := ExcelGen.addSheetFromCursor(l_ctxId, 'DBA Views', v_src, p_tabColor => 'green');
        BEGIN
            CLOSE v_src;
        EXCEPTION WHEN invalid_cursor THEN NULL;
        END;
        ExcelGen.setHeader(l_ctxId, l_sheet_handle, p_frozen => TRUE);
    --------
        v_email.add_attachment(
            p_file_name     => 'dba_views.xlsx'
            ,p_blob_content => ExcelGen.getFileContent(l_ctxId)
        );
    --------
        excelGen.closeContext(l_ctxId);
    END;

    v_email.add_paragraph('The attached spreadsheet should match what is in the html table above');
--dbms_output.put_line(v_email.body);
    v_email.send;
END;
```
### Sample Output
A snapshot from my email client follows. It is mentioned in the type definition comments
about *cursor_to_table* that spaces in the column names will be munged to _x0020_. I obviously forgot
and the "View Name" column heading is jacked. The attachment opens in Excel as expected.

 ![email snapshot](/images/email_snapshot.png)

### Mime Types

The attachment *mime type* values can be looked up from the file name extension
using the package *mime_type_pkg* that is optionally installed along with the object.
If you choose not to install that package, it will default to **text/plain** for
CLOB attachments and **application/octet-stream** for BLOBs. Honestly, modern email clients on
MS Windows seem to pay attention almost exclusively to the file extension, so I
do not think you will suffer any harm by sticking with these two defaults. Nevertheless,
we provide a way to do it right, and that is the default behavior if you use "install.sql".

### Type Specification

Although object attributes cannot be made private, you have 
no need for them. The object interface is through the methods.

The type is marked as NOT FINAL so that you can derive a subtype from it. Possible uses
involve adding methods for local conventions, such as a signature block, and perhaps
overriding or supplementing methods with localized html conventions.

It is recommended that you edit [install.sql](#installsql) before deploying to set suitable values 
for *smtp_server*, *reply_to* and *from_email_addr* define variables. The DEFAULT values
on the constructor parameters below are those currently defined in "install.sql".

```sql
    CONSTRUCTOR FUNCTION html_email_udt(
        -- these take strings that can have multiple comma separated email addresses
        p_to_list           VARCHAR2 DEFAULT NULL
        ,p_cc_list          VARCHAR2 DEFAULT NULL
        ,p_bcc_list         VARCHAR2 DEFAULT NULL
        --
        ,p_from_email_addr  VARCHAR2 DEFAULT 'donotreply@bogus.com'
        ,p_reply_to         VARCHAR2 DEFAULT 'donotreply@bogus.com'
        ,p_smtp_server      VARCHAR2 DEFAULT 'localhost'
        ,p_subject          VARCHAR2 DEFAULT NULL
        ,p_body             CLOB DEFAULT NULL
        -- compile time decision whether attribute 'log' is included
        ,p_log              app_log_udt DEFAULT NULL 
    ) RETURN SELF AS RESULT
    ,FINAL MEMBER PROCEDURE html_email_constructor(
        SELF IN OUT NOCOPY html_email_udt
        ,p_to_list          VARCHAR2 DEFAULT NULL
        ,p_cc_list          VARCHAR2 DEFAULT NULL
        ,p_bcc_list         VARCHAR2 DEFAULT NULL
        ,p_from_email_addr  VARCHAR2 DEFAULT '&&from_email_addr'
        ,p_reply_to         VARCHAR2 DEFAULT '&&reply_to'
        ,p_smtp_server      VARCHAR2 DEFAULT '&&smtp_server'
        ,p_subject          VARCHAR2 DEFAULT NULL
        ,p_body             CLOB DEFAULT NULL
        -- compile time decision whether attribute 'log' is included
        ,p_log              app_log_udt DEFAULT NULL

    --
    -- best explanation of method chaining rules I found is
    -- https://stevenfeuersteinonplsql.blogspot.com/2019/09/object-type-methods-part-3.html
    --
    ,FINAL MEMBER PROCEDURE send(SELF IN html_email_udt) -- cannot be in/out if we allow chaining it.
    ,MEMBER PROCEDURE add_paragraph(SELF IN OUT NOCOPY html_email_udt , p_clob CLOB)
    ,MEMBER FUNCTION  add_paragraph(p_clob CLOB) RETURN html_email_udt
    ,MEMBER PROCEDURE add_code_block(SELF IN OUT NOCOPY html_email_udt , p_clob CLOB)
    ,MEMBER FUNCTION  add_code_block(p_clob CLOB) RETURN html_email_udt
    ,MEMBER PROCEDURE add_to_body(SELF IN OUT NOCOPY html_email_udt, p_clob CLOB)
    ,MEMBER FUNCTION  add_to_body(p_clob CLOB) RETURN html_email_udt
    ,MEMBER PROCEDURE add_table_to_body( -- see cursor_to_table
        SELF IN OUT NOCOPY html_email_udt
        ,p_sql_string   CLOB            := NULL
        ,p_refcursor    SYS_REFCURSOR  := NULL
        ,p_caption      VARCHAR2        := NULL
    )
    ,MEMBER FUNCTION  add_table_to_body( -- see cursor_to_table
        p_sql_string    CLOB            := NULL
        ,p_refcursor    SYS_REFCURSOR  := NULL
        ,p_caption      VARCHAR2        := NULL
    ) RETURN html_email_udt
    -- these take strings that can have multiple comma separated email addresses
    ,MEMBER PROCEDURE add_to(SELF IN OUT NOCOPY html_email_udt, p_to VARCHAR2) 
    ,MEMBER FUNCTION  add_to(p_to VARCHAR2)  RETURN html_email_udt
    ,MEMBER PROCEDURE add_cc(SELF IN OUT NOCOPY html_email_udt, p_cc VARCHAR2)
    ,MEMBER FUNCTION  add_cc(p_cc VARCHAR2) RETURN html_email_udt
    ,MEMBER PROCEDURE add_bcc(SELF IN OUT NOCOPY html_email_udt, p_bcc VARCHAR2)
    ,MEMBER FUNCTION  add_bcc(p_bcc VARCHAR2) RETURN html_email_udt
    ,MEMBER PROCEDURE add_subject(SELF IN OUT NOCOPY html_email_udt, p_subject VARCHAR2)
    ,MEMBER FUNCTION  add_subject(p_subject VARCHAR2) RETURN html_email_udt
    ,MEMBER PROCEDURE add_attachment(
        SELF IN OUT NOCOPY html_email_udt
        ,p_file_name    VARCHAR2
        ,p_clob_content CLOB DEFAULT NULL
        ,p_blob_content BLOB DEFAULT NULL
        -- looks up the mime type from the file_name extension
    )
    ,MEMBER FUNCTION  add_attachment(
        p_file_name     VARCHAR2
        ,p_clob_content CLOB DEFAULT NULL
        ,p_blob_content BLOB DEFAULT NULL
        -- looks up the mime type from the file_name extension
    ) RETURN html_email_udt
    ,MEMBER PROCEDURE add_attachment( -- just in case you need fine control
        SELF IN OUT NOCOPY html_email_udt
        ,p_attachment   email_attachment_udt
    )
    ,MEMBER FUNCTION  add_attachment( -- just in case you need fine control
        p_attachment    email_attachment_udt
    ) RETURN html_email_udt
```

As a bonus it provides a static function to convert a cursor or query string 
into a CLOB containing an HTML table. You can include that in the email
or use it for a different purpose. It is called by member method *add_table_to_body*.
```sql
    --Note: that if the cursor does not return any rows, we silently pass back an empty clob
    ,STATIC FUNCTION cursor_to_table(
        -- pass in a string. 
        -- Unfortunately any tables that are not in your schema 
        -- will need to be fully qualified with the schema name.
        p_sql_string    CLOB            := NULL
        -- pass in an open cursor. This is better for my money.
        ,p_refcursor    SYS_REFCURSOR  := NULL
        -- if provided, will be the caption on the table, generally centered on the top of it
        -- by most renderers.
        ,p_caption      VARCHAR2        := NULL
        -- compile time decision whether attribute 'log' is included
        ,p_log              app_log_udt DEFAULT NULL 
    ) RETURN CLOB
```
### Privileges

The privs required to use *UTL_SMTP* and to
enable access to a network port for your schema may require some 
work from your DBA, and maybe the firewall and/or network team.
There is some information in comments in [install.sql](#installsql)
about Access Control Lists for the network priv.

A compile time option allows configuring with invoker rights (AUTHID CURRENT_USER) in
which case the calling schemas will require the network access control in addition
to the compiling schema.

The [Example](#example) shows using sendmail listening on port 25 on my 
local RHL database server (localhost), but you will likely need to use a 
company relay such as **smtp.mycompany.com**.
The administrator of the relay may even need to authorize your database machine
as a client. If the relay server complain about certificates, there is Oracle
documentation about configuring them. I have not done so.

### Method Chaining

One more example showing chaining of methods without ever declaring a variable
as one might use in an EXCEPTION block:
```sql
DECLARE
    l_var VARCHAR2(1);
BEGIN
    l_var := 'too much for the var size';
EXCEPTION WHEN OTHERS THEN
    html_email_udt(
            p_to_list => 'lee@linux2.localdomain'
            ,p_subject => 'error from procedure'
            ,p_smtp_server => 'localhost'
            ,p_body => 'Exception failed job xyz with the following information:'
        ).add_code_block(
            'sqlerrm   : '||SQLERRM
        ).add_code_block(
            'backtrace : '||DBMS_UTILITY.FORMAT_ERROR_BACKTRACE
        ).send
    ;
    RAISE;
END;
```
## install.sql

Runs each of these scripts in correct order and with compile options. There are a set
of five sqlplus "define" commands at the top that populate compile directives in
*PLSQL_CCFLAGS*.

    ALTER SESSION SET PLSQL_CCFLAGS='use_app_log:TRUE,use_app_parameter:FALSE,use_mime_type:TRUE,use_invoker_rights:FALSE';

There are three "define" statements for default values for the *html_email_udt* constructor
that should also be set appropriately. 

*install.sql* has directions allowing choice on whether
to use anything from the submodule. None is required except for the type *arr_varchar2_udt*
which is easy enough to replace. If you already have a 'TABLE OF VARCHAR2(4000)' object deployed,
look in the install script for the define of *array_varchar2_type*.
Set the variables to FALSE for any components you do not want.

