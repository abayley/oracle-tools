declare
    newline Varchar2(1) := chr(13);
    cr Varchar2(1) := chr(10);

    type QualName is record(
        owner Varchar2(200),
        name Varchar2(200),
        type Varchar2(200)
        );
    type QualNameList is table of QualName;

    type TableCols    is table of sys.all_tab_columns%rowtype;
    type ObjDeps      is table of sys.all_dependencies%rowtype;
    type ObjPrivs     is table of sys.all_tab_privs%rowtype;

    type Constraints  is table of sys.all_constraints%rowtype;
    type ConsCols     is table of sys.all_cons_columns%rowtype;

    type ColComments  is table of sys.all_col_comments%rowtype;

    type Indices      is table of sys.all_indexes%rowtype;

    type IxCol is record(
        index_name Varchar2(200),
        column_position Number,
        column_name Varchar2(200)
        );
    type IxCols is table of IxCol;

    type FkCol is record(
        constraint_name Varchar2(200),
        column_name Varchar2(200),
        r_owner Varchar2(200),
        r_table_name Varchar2(200),
        r_constraint_name Varchar2(200),
        r_column_name Varchar2(200)
        );
    type FkCols is table of FkCol;


    procedure emit(s Varchar2) is
    begin
        -- If the last char is a newline, strip it and use put_line to emit.
        -- This prevents the dbms_output line buffer from overflowing.
        if substr(s, -1) = newline or substr(s, -1) = cr then
            dbms_output.put_line(substr(s, 1, length(s) - 1));
        else
            dbms_output.put(s);
        end if;
    end;


    procedure emitln(s Varchar2) is
    begin
        dbms_output.put_line(s);
    end;


    procedure debug(s Varchar2) is
    begin
        null;
        -- dbms_output.put_line(to_char(systimestamp, 'hh24:mi:ss.ff') || '  ' || s);
    end;


    function get_tab_cols(desc_owner Varchar2, desc_name Varchar2) return TableCols is
        tc TableCols;
    begin
        select tc.* bulk collect into tc
        from sys.all_tab_columns tc
        where tc.table_name = desc_name and tc.owner = desc_owner
        order by tc.column_id
        ;
        return tc;
    end;


    function get_col_comments(desc_owner Varchar2, desc_name Varchar2) return ColComments is
        col_comments ColComments;
    begin
        select cc.* bulk collect into col_comments
        from sys.all_col_comments cc
        where cc.table_name = desc_name and cc.owner = desc_owner
        order by cc.column_name
        ;
        return col_comments;
    end;


    function get_cons_cols(desc_owner Varchar2, desc_name Varchar2) return ConsCols is
        cons_cols ConsCols;
    begin
        select cc.* bulk collect into cons_cols
        from sys.dual
        join sys.all_constraints c on 1=1
            and c.owner = desc_owner
            and c.table_name = desc_name
        join sys.all_cons_columns cc on 1=1
            and cc.constraint_name = c.constraint_name
            and cc.owner = c.owner
            and cc.table_name = c.table_name
        order by cc.position
        ;
        return cons_cols;
    end;


    function get_constraints(desc_owner Varchar2, desc_name Varchar2) return Constraints is
        cons Constraints;
    begin
        select c.* bulk collect into cons
        from sys.all_constraints c
        where 1=1
        and c.owner = desc_owner
        and c.table_name = desc_name
        and c.constraint_name not like 'SYS%'
        order by c.constraint_name
        ;
        return cons;
    end;


    function get_ix_cols(desc_owner Varchar2, desc_name Varchar2) return IxCols is
        index_cols IxCols;
    begin
        select
              ic.index_name
            , ic.column_position
            , ic.column_name
            bulk collect into index_cols
        from sys.dual
        join sys.all_ind_columns ic on 1=1
            and ic.table_name = desc_name
            and ic.table_owner = desc_owner
            and not exists
            (
                select c.index_name
                from sys.all_constraints c
                where 1=1
                and c.constraint_type in ('P', 'U')
                and c.index_name = ic.index_name
                and c.table_name = ic.table_name
                and c.owner = ic.index_owner
            )
        order by ic.index_name, ic.column_position
        ;
        return index_cols;
    end;


    function get_indexes(desc_owner Varchar2, desc_name Varchar2) return Indices is
        ixs Indices;
    begin
        select i.* bulk collect into ixs
        from sys.all_indexes i
        where 1=1
        and i.table_name = desc_name
        and i.table_owner = desc_owner
        order by i.index_name
        ;
        return ixs;
    end;


    -- Populate FkCols collection for a single constraint.
    function get_fk_cols
        ( cons_owner Varchar2
        , cons_name Varchar2
        , table_name Varchar2
        , r_cons_owner Varchar2
        , r_cons_name Varchar2
        , r_table_name Varchar2
        ) return FkCols is
        fk_cols FkCols;
    begin
        select
              cc.constraint_name
            , cc.column_name
            , rcc.owner as r_owner
            , rcc.table_name as r_table_name
            , rcc.constraint_name as r_constraint_name
            , rcc.column_name as r_column_name
            bulk collect into fk_cols
        from sys.dual
        join sys.all_cons_columns cc on 1=1
            and cc.owner = cons_owner
            and cc.table_name = table_name
            and cc.constraint_name = cons_name
        join sys.all_cons_columns rcc on 1=1
            and rcc.owner = r_cons_owner
            and rcc.constraint_name = r_cons_name
            and rcc.owner = r_cons_owner
            and rcc.table_name = r_table_name
            and rcc.position = cc.position
        order by cc.position
        ;
        return fk_cols;
    end;


    -- Loop over FK constraints, get cols for each, and accumulate into
    -- a single collection for consumer.
    function get_fk_cols(desc_owner Varchar2, desc_name Varchar2) return FkCols is
        fk_cols FkCols := FkCols();
        fk_cols_tmp FkCols;
    begin
        for cons in (
            select
                  c.owner
                , c.constraint_name as cons_name
                , c.table_name
                , c.r_owner
                , c.r_constraint_name as r_cons_name
                , rc.table_name as r_table_name
            from sys.dual
            join sys.all_constraints c on 1=1
                and c.owner = desc_owner
                and c.table_name = desc_name
                and c.constraint_type = 'R'
            join sys.all_constraints rc on 1=1
                and rc.owner = c.r_owner
                and rc.constraint_name = c.r_constraint_name
            order by c.owner, c.constraint_name
            )
        loop
            fk_cols_tmp := get_fk_cols(cons.owner, cons.cons_name, cons.table_name
                , cons.r_owner, cons.r_cons_name, cons.r_table_name);
            fk_cols := fk_cols multiset union all fk_cols_tmp;
        end loop;
        return fk_cols;
    end;


    -- I would prefer to use this function to get FK cols,
    -- but performance is variable. Sometimes quick, sometimes ~10s.
    function get_fk_cols_old(desc_owner Varchar2, desc_name Varchar2) return FkCols is
        fk_cols FkCols;
    begin
        -- This can be slow. I cannot do explain plan, so I'm stuck...
        select
              cc.constraint_name
            , cc.column_name
            , rcc.owner as r_owner
            , rcc.table_name as r_table_name
            , rcc.constraint_name as r_constraint_name
            , rcc.column_name as r_column_name
            bulk collect into fk_cols
        from sys.dual
        join sys.all_constraints c on 1=1
            and c.owner = desc_owner
            and c.table_name = desc_name
            and c.constraint_type = 'R'
        join sys.all_cons_columns cc on 1=1
            and cc.owner = desc_owner
            and cc.table_name = desc_name
            and cc.owner = c.owner
            and cc.table_name = c.table_name
            and cc.constraint_name = c.constraint_name
        join sys.all_constraints rc on 1=1
            and rc.owner = c.r_owner
            and rc.constraint_name = c.r_constraint_name
        join sys.all_cons_columns rcc on 1=1
            and rcc.owner = c.r_owner
            and rcc.constraint_name = c.r_constraint_name
            and rcc.constraint_name = rc.constraint_name
            and rcc.owner = rc.owner
            and rcc.table_name = rc.table_name
            and rcc.position = cc.position
        order by c.owner, c.constraint_name, cc.position
        ;
        return fk_cols;
    end;


    function get_deps(desc_owner Varchar2, desc_name Varchar2) return ObjDeps is
        obj_deps ObjDeps;
    begin
        select * bulk collect into obj_deps
        from sys.all_dependencies
        where 1=1
        and referenced_owner = desc_owner
        and referenced_name = desc_name
        order by owner, name, type
        ;
        return obj_deps;
    end;


    function get_privs(desc_owner Varchar2, desc_name Varchar2) return ObjPrivs is
        obj_privs ObjPrivs;
    begin
        select * bulk collect into obj_privs
        from sys.all_tab_privs p
        where 1=1
        and p.table_schema = desc_owner
        and p.table_name = desc_name
        ;
        return obj_privs;
    end;


    function col_in_ix(col Varchar2, ix_cols IxCols) return Number is
    begin
        for i in 1..ix_cols.count loop
            if ix_cols(i).column_name = col then
                return ix_cols(i).column_position;
            end if;
        end loop;
        return 0;
    end;


    function fk_cols_ref(col Varchar2, fk_cols FkCols) return Varchar2 is
        c FkCol;
    begin
        for i in 1..fk_cols.count loop
            if fk_cols(i).column_name = col then
                c := fk_cols(i);
                return lower(c.r_owner || '.' || c.r_table_name || '.' || c.r_column_name
                    || ' (' || c.constraint_name || ')');
            end if;
        end loop;
        return '';
    end;


    function format_index_cols(ix sys.all_indexes%rowtype, ix_cols IxCols) return Varchar2 is
        s Varchar2(2000) := '';
    begin
        for i in 1..ix_cols.count loop
            if ix.index_name = ix_cols(i).index_name then
                if s is null then
                    s := lower(ix_cols(i).column_name);
                else
                    s := s || ', ' || lower(ix_cols(i).column_name);
                end if;
            end if;
        end loop;
        return s;
    end;


    function format_obj_dep(dep sys.all_dependencies%rowtype) return Varchar2 is
    begin
        return '    ' || lower(dep.owner) || '.' || lower(dep.name) || ' (' || dep.type || ')';
    end;


    procedure emit_deps_type(obj_deps ObjDeps, obj_type Varchar2, prefix Varchar2) is
        emit_header Boolean := True;
        dep sys.all_dependencies%rowtype;
        type_suffix Varchar2(200) := '';
    begin
        for i in 1 .. obj_deps.count loop
            dep := obj_deps(i);
            if dep.type = upper(obj_type) or obj_type is null then
                if emit_header then
                    emit_header := False;
                    emitln(prefix || obj_type);
                end if;
                if obj_type is null then
                    type_suffix := '  (' || dep.type || ')';
                end if;
                emitln(prefix || '    ' || lower(dep.owner) || '.' || lower(dep.name) || type_suffix);
            end if;
        end loop;
    end;


    procedure emit_deps(desc_owner Varchar2, desc_name Varchar2, comment Boolean := False) is
        obj_deps ObjDeps;
        prefix Varchar2(3) := '-- ';
    begin
        if not comment then
            prefix := '';
        end if;
        obj_deps := get_deps(desc_owner, desc_name);
        if obj_deps.count > 0 then
            emitln('');
            emitln(prefix || 'Referenced by:');
            -- emit_deps_type(obj_deps, null, prefix);
            -- return;
            emit_deps_type(obj_deps, 'View', prefix);
            emit_deps_type(obj_deps, 'Trigger', prefix);
            emit_deps_type(obj_deps, 'Package', prefix);
            emit_deps_type(obj_deps, 'Package Body', prefix);
            emit_deps_type(obj_deps, 'Synonym', prefix);
        end if;
    end;


    procedure emit_privs(desc_owner Varchar2, desc_name Varchar2) is
        privs ObjPrivs := ObjPrivs();
    begin
        privs := get_privs(desc_owner, desc_name);
        for i in 1..privs.count loop
            emitln('grant ' || lower(privs(i).privilege) || ' on ' || desc_owner || '.' || desc_name ||' to ' || lower(privs(i).grantee) || ';');
        end loop;
    end;


    procedure desc_source(src_type Varchar2, desc_owner Varchar2, desc_name Varchar2, max_line Number := 0) is
        cursor source is
        select s.line, s.text
        from sys.all_source s
        where s.owner = desc_owner and s.name = desc_name and s.type = src_type
        and (s.line <= max_line or max_line = 0)
        order by s.name, s.type, s.line
        ;
        emit_header Boolean := True;
    begin
        for s in source loop
            if emit_header then
                emit_header := False;
                emitln('');
                emit('create or replace ');
            end if;
            emit(s.text);
        end loop;
        if not emit_header then
            emitln('');
            emitln('/');
            emitln('show errors');
            emitln('');
            emit_privs(desc_owner, desc_name);
        end if;
    end;


    procedure desc_source_linenums(src_type Varchar2, desc_owner Varchar2, desc_name Varchar2) is
        l Char(6);
        cursor source is
        select s.line, s.text
        from sys.all_source s
        where s.owner = desc_owner and s.name = desc_name and s.type = src_type
        order by s.name, s.type, s.line
        ;
    begin
        emitln('');
        for s in source loop
            l := to_char(s.line);
            if s.line = 1 then
                emit(l || '  create or replace ' || s.text);
            else
                emit(l || '  ' || s.text);
            end if;
        end loop;
    end;


    procedure desc_procedure(desc_owner Varchar2, desc_name Varchar2) is
    begin
        -- TODO: make short and long verions of this
        emit_deps(desc_owner, desc_name, True);
        desc_source('PROCEDURE', desc_owner, desc_name);
    end;


    procedure desc_function(desc_owner Varchar2, desc_name Varchar2) is
    begin
        -- TODO: make short and long verions of this
        emit_deps(desc_owner, desc_name, True);
        desc_source('FUNCTION', desc_owner, desc_name);
    end;


    procedure desc_type(desc_owner Varchar2, desc_name Varchar2) is
    begin
        -- TODO: make short and long verions of this
        emit_deps(desc_owner, desc_name, True);
        desc_source('TYPE', desc_owner, desc_name);
    end;


    procedure desc_package(desc_owner Varchar2, desc_name Varchar2, full Boolean) is
    begin
        emit_deps(desc_owner, desc_name, True);
        desc_source('PACKAGE', desc_owner, desc_name);
        if full then
            emitln('');
            desc_source('PACKAGE BODY', desc_owner, desc_name);
        end if;
    end;


    procedure desc_trigger(desc_owner Varchar2, desc_name Varchar2, full Boolean) is
    begin
        if full then
            desc_source('TRIGGER', desc_owner, desc_name);
        else
            desc_source('TRIGGER', desc_owner, desc_name, 3);
        end if;
    end;


    procedure desc_sequence(desc_owner Varchar2, desc_name Varchar2, full Boolean) is
        last_used Char(32);
        max_value Char(32);
        min_value Char(32);
    begin
        for seq in (
            select *
            from sys.all_sequences s
            where 1=1
            and s.sequence_name = desc_name
            and s.sequence_owner = desc_owner
            ) loop
            last_used := to_char(seq.last_number);
            max_value := to_char(seq.max_value);
            min_value := to_char(seq.min_value);
            emitln('Sequence ' || desc_owner || '.' || desc_name);
            emitln('------------------------------+-------------------------------+---------------');
            emitln('Last used                     | Rollover                      | Start');
            emitln('------------------------------+-------------------------------+---------------');
            emitln(last_used || max_value || min_value);
            emitln('------------------------------------------------------------------------------');
        end loop;
        if full then
            emit_deps(desc_owner, desc_name);
        end if;
    end;


    procedure emit_table_triggers(tbl_owner Varchar2, tbl_name Varchar2) is
        cursor triggers is
        select
              t.owner
            , t.trigger_name
            , t.trigger_type
            -- , action_type
            -- , before_statement
            -- , before_row
            -- , after_row
            -- , after_statement
            -- , instead_of_row
            , t.triggering_event
        from sys.all_triggers t
        where t.table_owner = tbl_owner and t.table_name = tbl_name
        ;
    begin
        for t in triggers loop
            emitln(lower('trigger ' || t.owner || '.' || t.trigger_name || ' ' || t.triggering_event || ' ' || t.trigger_type));
        end loop;
    end;


    procedure emit_col_comment(col Varchar2, col_comments ColComments) is
    begin
        for i in 1..col_comments.count loop
            if col_comments(i).column_name = col and col_comments(i).comments is not null then
                emit('    "');
                emit(col_comments(i).comments);
                emitln('"');
            end if;
        end loop;
    end;


    procedure emit_object_comment(desc_owner Varchar2, desc_name Varchar2) is
        cursor comments is
        select tc.comments from sys.all_tab_comments tc
        where tc.table_name = desc_name and tc.owner = desc_owner
        ;
    begin
        for c in comments loop
            if c.comments is not null then
                emit('    "');
                emit(c.comments);
                emitln('"');
            end if;
        end loop;
    end;


    procedure desc_view_body(desc_owner Varchar2, desc_name Varchar2) is
        cursor cols is
        select case tc.column_id when 1 then '( ' else ', ' end || tc.column_name as column_name
        from sys.all_tab_columns tc
        where tc.table_name = desc_name and tc.owner = desc_owner
        order by tc.column_id
        ;
        cursor body is
        select v.text from sys.all_views v
        where v.view_name = desc_name and v.owner = desc_owner
        ;
    begin
        emitln('create or replace view ' || desc_owner || '.' || desc_name);
        for col in cols loop
            emitln(col.column_name);
        end loop;
        emitln(') as');
        for b in body loop
            emitln(b.text);
        end loop;
    end;


    procedure emit_index(ix sys.all_indexes%rowtype, ix_cols IxCols) is
        uniqueness Varchar2(20) := '';
    begin
        if ix.uniqueness = 'UNIQUE' then
            uniqueness := ' unique';
        end if;
        uniqueness := ' ' || ix.uniqueness;
        emitln(lower(ix.index_type) || ' index ' || lower(ix.index_name) || uniqueness || ' (' || format_index_cols(ix, ix_cols) || ')');
    end;


    function is_constraint_index(ix sys.all_indexes%rowtype, cons Constraints) return Boolean is
    begin
        for i in 1..cons.count loop
            if cons(i).index_name = ix.index_name and nvl(cons(i).index_owner, cons(i).owner) = ix.owner then
                return True;
            end if;
        end loop;
        return False;
    end;


    function index_tablespace(index_name Varchar2, indxes Indices) return Varchar2 is
    begin
        for i in 1..indxes.count loop
            if indxes(i).index_name = index_name then
                return lower(indxes(i).tablespace_name);
            end if;
        end loop;
        return to_char(null);
    end;


    function format_cons_cols(cons sys.all_constraints%rowtype, cols ConsCols) return Varchar2 is
        s Varchar2(2000) := '';
    begin
        for i in 1..cols.count loop
            if cons.constraint_name = cols(i).constraint_name then
                if s is null then
                    s := lower(cols(i).column_name);
                else
                    s := s || ', ' || lower(cols(i).column_name);
                end if;
            end if;
        end loop;
        return s;
    end;


    procedure emit_uq_cons(con sys.all_constraints%rowtype, cons_cols ConsCols, index_tablespace Varchar2) is
    begin
        emitln('constraint ' || lower(con.constraint_name) || ' unique (' || format_cons_cols(con, cons_cols) || ')');
    end;


    procedure emit_check_cons(cons sys.all_constraints%rowtype) is
    begin
        emitln('constraint ' || lower(cons.constraint_name) || ' check (' || cons.search_condition || ')');
    end;


    function col_in_cons(column_name Varchar2, cons_type Varchar2, cons Constraints, cons_cols ConsCols) return Varchar2 is
    begin
        for i in 1..cons.count loop
            if cons(i).constraint_type = cons_type then
                for j in 1..cons_cols.count loop
                    if cons_cols(j).constraint_name = cons(i).constraint_name and cons_cols(j).column_name = column_name then
                        return cons_type || to_char(cons_cols(j).position);
                    end if;
                end loop;
            end if;
        end loop;
        return '';
    end;


    function format_col
        ( col sys.all_tab_columns%rowtype
        , cons Constraints
        , cons_cols ConsCols
        , ix_cols IxCols
        , fk_cols FkCols
    ) return Varchar2 is
        name Char(35) := lower(col.column_name);
        params Varchar2(200);
        parens Varchar2(200);
        nulls Varchar2(50);
        datatype Char(35);
        pk Char(5);
        uq Char(5);
        ix Char(5);
        ix_col Number;
        fk Varchar2(400);
        defalt Varchar2(2000);
    begin
        if col.data_type = 'VARCHAR2' then
            params := to_char(col.data_length);
        end if;
        if col.data_type = 'NUMBER'
            and col.data_precision is not null
            and col.data_scale is not null then
            params := to_char(col.data_precision) || ', ' || to_char(col.data_scale);
        end if;
        if params is not null then
            parens := '(' || params || ')';
        end if;
        if col.nullable = 'N' then
            nulls := ' not null';
        end if;
        if col.default_length > 0 then
            defalt := ' default ' || to_char(col.data_default);
        end if;
        datatype := substr(lower(col.data_type) || parens || nulls || defalt, 1, 35);
        --
        pk := col_in_cons(col.column_name, 'P', cons, cons_cols);
        uq := col_in_cons(col.column_name, 'U', cons, cons_cols);
        --
        ix := '';
        ix_col := col_in_ix(col.column_name, ix_cols);
        if ix_col > 0 then
            ix := 'I' || to_char(ix_col);
        end if;
        --
        fk := fk_cols_ref(col.column_name, fk_cols);
        return name || pk || uq || ix || datatype || fk;
    end;


    procedure desc_view(desc_owner Varchar2, desc_name Varchar2, full Boolean) is
        tab_cols TableCols;
        cons Constraints := Constraints();
        cons_cols ConsCols := ConsCols();
        ix_cols IxCols := IxCols();
        fk_cols FkCols := FkCols();
        col_comments ColComments;
        comment Varchar2(4000);
    begin
        tab_cols := get_tab_cols(desc_owner, desc_name);
        col_comments := get_col_comments(desc_owner, desc_name);

        emitln('View ' || desc_owner || '.' || desc_name);
        emit_object_comment(desc_owner, desc_name);
        emitln('------------------------------------------------+------------------------------');
        emitln('column                                          | type');
        emitln('------------------------------------------------+------------------------------');
        for i in 1..tab_cols.count loop
            emitln(format_col(tab_cols(i), cons, cons_cols, ix_cols, fk_cols));
            emit_col_comment(tab_cols(i).column_name, col_comments);
        end loop;
        emitln('');
        emit_privs(desc_owner, desc_name);
        if full then
            emit_deps(desc_owner, desc_name);
        end if;
        emitln('-------------------------------------------------------------------------------');
        if full then
            emitln('');
            desc_view_body(desc_owner, desc_name);
        end if;
    end;


    function table_attribs(table_dtl sys.all_tables%rowtype, pk_tablespace Varchar2) return Varchar2 is
        s Varchar2(200);
    begin
        if table_dtl.temporary = 'Y' then
            s := 'temporary';
        else
            s := 'tablespace ';
            if table_dtl.iot_type = 'IOT' then
                s := s || pk_tablespace || ' organization index';
            else
                s := s || lower(table_dtl.tablespace_name);
            end if;
            if table_dtl.logging = 'NO' then
                s := s || ' nologging';
            end if;
        end if;
        return s;
    end;


    procedure desc_table(desc_owner Varchar2, desc_name Varchar2, full Boolean := False) is
        table_dtl sys.all_tables%rowtype;
        tab_cols TableCols;
        cons Constraints := Constraints();
        cons_cols ConsCols := ConsCols();
        fk_cols FkCols := FkCols();
        indxes Indices := Indices();
        ix_cols IxCols := IxCols();
        col_comments ColComments;
        first_col Boolean := True;
        pk_tablespace Varchar2(30);
        cursor tab_cr is
        select t.*
        from sys.all_tables t
        where t.table_name = desc_name and t.owner = desc_owner
        ;
    begin
        debug('get table details');
        for t in tab_cr loop
            table_dtl := t;
        end loop;
        tab_cols := get_tab_cols(desc_owner, desc_name);
        cons := get_constraints(desc_owner, desc_name);
        cons_cols := get_cons_cols(desc_owner, desc_name);
        indxes  := get_indexes(desc_owner, desc_name);
        ix_cols := get_ix_cols(desc_owner, desc_name);
        debug('get fks');
        fk_cols := get_fk_cols(desc_owner, desc_name);
        col_comments := get_col_comments(desc_owner, desc_name);
        debug('print DDL');
        for i in 1..cons.count loop
            if cons(i).constraint_type = 'P' then
                pk_tablespace := index_tablespace(cons(i).index_name, indxes);
            end if;
        end loop;

        emit('Table ' || desc_owner || '.' || desc_name);
        emitln(' (' || table_attribs(table_dtl, pk_tablespace) || ')');
        emit_object_comment(desc_owner, desc_name);
        emitln('---------------------------------+----+----+----+----------------------------------+-----------------------------');
        emitln('column                           | PK | Uq | Ix | type                             | FKs');
        emitln('---------------------------------+----+----+----+----------------------------------+-----------------------------');

        for i in 1..tab_cols.count loop
            emitln(format_col(tab_cols(i), cons, cons_cols, ix_cols, fk_cols));
            emit_col_comment(tab_cols(i).column_name, col_comments);
        end loop;
        -- If there are some constraints/indexes to emit then insert a
        -- blank line here, for a visual break.
        if cons.count + indxes.count > 0 then
            emitln('');
        end if;
        for i in 1 .. cons.count loop
            if cons(i).constraint_type = 'U' then
                emit_uq_cons(cons(i), cons_cols, index_tablespace(cons(i).constraint_name, indxes));
            end if;
        end loop;
        for i in 1 .. cons.count loop
            if cons(i).constraint_type = 'C' then
                emit_check_cons(cons(i));
            end if;
        end loop;
        if indxes.count > 0 then
            for i in 1 .. indxes.count loop
                if not is_constraint_index(indxes(i), cons) then
                    emit_index(indxes(i), ix_cols);
                end if;
            end loop;
        end if;
        emit_table_triggers(desc_owner, desc_name);
        emit_privs(desc_owner, desc_name);
        if full then
            emit_deps(desc_owner, desc_name);
        end if;
        emitln('-----------------------------------------------------------------------------------------------------------------');
        debug('done');
    end;


    function resolve_name(desc_owner Varchar2, desc_name Varchar2) return QualNameList is
        -- if owner is null, look for public synonym matching name. if found, resolve.
        -- otherwise look for object in user schema.
        -- otherwise look for any object matching name.
        cursor pub_syn is
        select s.table_owner, s.table_name
        from sys.all_synonyms s
        where s.owner = nvl(desc_owner, 'PUBLIC') and s.synonym_name = desc_name
        ;
        cursor user_obj is
        select o.owner, o.object_name, o.object_type
        from sys.all_objects o
        where o.owner = nvl(desc_owner, user) and o.object_name = desc_name
        ;
        cursor any_obj is
        select o.owner, o.object_name, o.object_type
        from sys.all_objects o
        where o.owner = nvl(desc_owner, owner) and o.object_name = desc_name
        ;
        qnl QualNameList := QualNameList();
    begin
        -- debug('find ' || desc_owner || '.' || desc_name);
        for s in pub_syn loop
            -- debug('public syn ' || s.table_owner || '.' || s.table_name);
            return resolve_name(s.table_owner, s.table_name);
        end loop;
        for o in user_obj loop
            -- debug('user ' || o.owner || '.' || o.object_name);
            qnl.extend;
            qnl(qnl.last).owner := o.owner;
            qnl(qnl.last).name := o.object_name;
            qnl(qnl.last).type := o.object_type;
            return qnl;
        end loop;
        for o in any_obj loop
            -- debug('any ' || o.owner || '.' || o.object_name);
            qnl.extend;
            qnl(qnl.last).owner := o.owner;
            qnl(qnl.last).name := o.object_name;
            qnl(qnl.last).type := o.object_type;
        end loop;
        return qnl;
    end;


    function split_owner_obj(s Varchar2) return QualName is
        qname QualName;
        pos Number := nvl(instr(s, '.'), 0);
    begin
        qname.owner := null;
        qname.name := substr(lower(s), pos+1);
        if pos > 1 then
            qname.owner := substr(lower(s), 1, pos-1);
        end if;
        return qname;
    end;


    procedure describe(obj_name Varchar2, full Varchar2 := 'N') is
        qn QualName;
        qnl QualNameList;
        fullb Boolean := (full = 'Y');
    begin
        if obj_name is null then
            return;
        end if;
        qn := split_owner_obj(obj_name);
        debug('resolve name');
        qnl := resolve_name(upper(qn.owner), upper(qn.name));
        if qnl.count = 0 then
            emitln('No object found matching ' || obj_name);
            return;
        end if;

        qn := qnl(qnl.first);
        debug(qn.type || ' : ' || qn.owner || '.' || qn.name);

        if qn.type = 'TABLE' then
            desc_table(qn.owner, qn.name, fullb);
            return;
        end if;

        if qn.type = 'VIEW' then
            desc_view(qn.owner, qn.name, fullb);
            return;
        end if;

        if qn.type = 'SEQUENCE' then
            desc_sequence(qn.owner, qn.name, fullb);
            return;
        end if;

        if qn.type = 'PACKAGE' then
            desc_package(qn.owner, qn.name, fullb);
            return;
        end if;

        if qn.type = 'TRIGGER' then
            desc_trigger(qn.owner, qn.name, fullb);
            return;
        end if;

        if qn.type = 'PROCEDURE' then
            desc_procedure(qn.owner, qn.name);
            return;
        end if;

        if qn.type = 'FUNCTION' then
            desc_function(qn.owner, qn.name);
            return;
        end if;

        if qn.type = 'TYPE' then
            desc_type(qn.owner, qn.name);
            return;
        end if;

        emitln('-- I found this but don''t know how to handle it: ' || qn.type || ' : ' || qn.owner || '.' || qn.name);
        emitln('-- Falling back to dbms_metadata.get_ddl:');
        emitln(dbms_metadata.get_ddl(qn.type, qn.name, qn.owner));
        emitln(';');
        emit_privs(qn.owner, qn.name);
    end;


    procedure search(search_text Varchar2) is
        cursor source is
        select s.owner, s.name, s.type, s.line, s.text
        from sys.all_source s
        where lower(s.text) like '%' || lower(search_text) || '%'
        order by s.owner, s.name, s.type, s.line
        ;
        cursor objects is
        select o.owner, o.object_name, o.object_type
        from sys.all_objects o
        where lower(o.object_name) like '%' || lower(search_text) || '%'
        order by o.owner, o.object_name, o.object_type
        ;
        cursor tcolumns is
        select tc.owner, tc.table_name, tc.column_name
        from sys.all_tab_columns tc
        where lower(tc.column_name) like '%' || lower(search_text) || '%'
        order by tc.owner, tc.table_name, tc.column_name
        ;
    begin
        for s in objects loop
            emitln(s.owner || '.' || s.object_name || ': ' || s.object_type);
        end loop;
        for s in tcolumns loop
            emitln(s.owner || '.' || s.table_name || ': column ' || s.column_name);
        end loop;
        for s in source loop
            emit(s.owner || '.' || s.name || ': ' || to_char(s.line) || ': ' || s.text);
        end loop;
    end;


    procedure source(module Varchar2) is
        qn QualName;
        qnl QualNameList;
    begin
        qn := split_owner_obj(module);
        qnl := resolve_name(upper(qn.owner), upper(qn.name));
        if qnl.count = 0 then
            emitln('No object found matching ' || module);
            return;
        end if;

        qn := qnl(qnl.first);
        debug(qn.type || ' : ' || qn.owner || '.' || qn.name);
        if qn.type in ('PACKAGE', 'PROCEDURE', 'FUNCTION', 'TRIGGER', 'TYPE') then
            desc_source_linenums(qn.type, qn.owner, qn.name);
            if qn.type = 'PACKAGE' then
                emitln('');
                desc_source_linenums('PACKAGE BODY', qn.owner, qn.name);
            end if;
            return;
        end if;
        emitln('I found this but don''t know how to handle it: ' || qn.type || ' : ' || qn.owner || '.' || qn.name);
    end;

begin
    if '&1' = 'DESC' then
        describe('&2', '&3');
    end if;
    if '&1' = 'SOURCE' then
        source('&2');
    end if;
    if '&1' = 'SEARCH' then
        search('&2');
    end if;
end;
/

