oracle-tools
============
These are SQL\*Plus scripts (and other goodies) that make working with Oracle via SQL\*Plus a bit less crap.


Install
=======
Create an SQLPATH directory e.g.

    mkdir $HOME/.oracle
    export SQLPATH=$HOME/.oracle  # add to your $HOME/.profile

On Windows, make a new environment variable for SQLPATH (the Oracle install directory works for me):

    SQLPATH: C:\instantclient10_1

Copy all the sqlpath files into $SQLPATH.

 * Read more about login.sql:
  * http://docs.oracle.com/cd/B28359_01/server.111/b31189/ch2.htm#i1133106
 * Read more about sqlplus commands and settings:
  * http://www.toadworld.com/platforms/oracle/w/wiki/3963.sql-plus.aspx
  * http://www.orafaq.com/wiki/SQL*Plus_FAQ
  * http://stackoverflow.com/questions/1439203/favorite-sqlplus-tips-and-tricks


Using rlwrap
============

If you're using sqlplus directly from the terminal, run with rlwrap:

    rlwrap sqlplus username/password@oracle.server:1521/sid

Before you do, though, create an RLWRAP_HHOME folder and set permissions so that only you can see it.
That's because rlwrap stores everything in a history file, including console-entered passwords.

    mkdir $HOME/.rlwrap
    chmod 700 $HOME/.rlwrap

Edit $HOME/.profile and add this line:

    export RLWRAP_HOME=$HOME/.rlwrap

For password-less logins you need to quote the bit after the @, and escape the quotes (sqlplus will barf if you don't):

    rlwrap sqlplus username@\"test.oracle.corp:1521/opstest\"

See http://blog.oracle48.nl/sqlplus-and-easy-connect-without-password-on-the-command-line/ for the gory details.


SQL\*Plus Wrapper
================

I prefer to use wrapper scripts to invoke sqlplus, with these advantages:

 * don't have to enter long connection URLs
 * pipe output through GNU source-highlight (when appropriate)
 * can use interactively or batch; enables rlwrap when appropriate

I use a worker script - $SQLPATH/runsqlplus - and an invoker script for each login
(this contains the authentication information, so you need to be careful with permissions).

This is an example invoker script:

    $SQLPATH/runsqlplus username/password@\"oracle.server:1521/sid\" $*

I have this in my $HOME/.bin directory, which is in my path. The directory and the scripts all have permissions 700.


Catalog Browsing
================

Oracle's built-in describe is a bit poo, so I've built a better one, in $SQLPATH/extended_describe.sql.

Create an sqlplus wrapper script for each function.
This makes it behave a bit more like the postgres describe (and extended describe).
(One nice thing about using an sqlplus script as a wrapper is that you do not need to quote the object name.)

e.g.

 * basic describe: $SQLPATH/d.sql

        set define on feedback off serveroutput on size unlimited format wrapped
        @extended_describe DESC &1 N
        prompt
        set feedback on

 * extended describe: $SQLPATH/d+.sql

        set define on feedback off serveroutput on size unlimited format wrapped
        @extended_describe DESC &1 Y
        prompt
        set feedback on

 * search: $SQLPATH/s.sql

        set define on feedback off serveroutput on size unlimited format wrapped
        @extended_describe SEARCH &1 ''
        set feedback on

 * source (with line numbers): $SQLPATH/src.sql

        set define on feedback off serveroutput on size unlimited format wrapped
        @extended_describe SOURCE &1 ''
        set feedback on

and then you invoke in an sqlplus session like so:

    @d+ all_objects

Or, if you use the sqlplus wrapper scripts described above:

    echo '@d+ all_objects' | npcprod


Source Highlight
================

The files in source-highlight can be copied to /usr/share/source-highlight/.

