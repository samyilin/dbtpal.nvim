" dbt jinja + SQL syntax file
" Language: dbt Jinja SQL
" Maintainer: Pedram Navid <pedram@pedramnavid.com>
" Last Change: Feb 25, 2024

if exists("b:current_syntax")
    finish
endif

" Import default SQL syntax
runtime! syntax/sql.vim

" sqlFold uses contains=ALL, which lets Jinja keywords shadow SQL keywords
" outside {{ }} blocks. Redefine it with the Jinja keyword groups excluded;
" template regions below still list them in their own contains.
if hlexists("sqlFold")
    syn clear sqlFold
    syn region sqlFold start='^\s*\zs\c\(Create\|Update\|Alter\|Select\|Insert\)' end=';$\|^$' transparent fold contains=ALLBUT,jinjaStatement,jinjaFilter,jinjaTest,jinjaFunction
endif

syntax case ignore


" Borrowed from lepture/vim-jinja, these are jinja specific
" keywords that are matched withi jinja regions {{ .. }} and
" {% ... %}
syn keyword jinjaStatement contained containedin=dbtJinjaTemplate if else elif endif is not
syn keyword jinjaStatement contained containedin=dbtJinjaTemplate for in recursive endfor
syn keyword jinjaStatement contained containedin=dbtJinjaTemplate raw endraw
syn keyword jinjaStatement contained containedin=dbtJinjaTemplate block endblock extends super scoped
syn keyword jinjaStatement contained containedin=dbtJinjaTemplate macro endmacro call endcall
syn keyword jinjaStatement contained containedin=dbtJinjaTemplate from import as do continue break
syn keyword jinjaStatement contained containedin=dbtJinjaTemplate filter endfilter set endset
syn keyword jinjaStatement contained containedin=dbtJinjaTemplate include ignore missing
syn keyword jinjaStatement contained containedin=dbtJinjaTemplate with without context endwith
syn keyword jinjaStatement contained containedin=dbtJinjaTemplate trans endtrans pluralize
syn keyword jinjaStatement contained containedin=dbtJinjaTemplate autoescape endautoescape

hi def link jinjaStatement Statement

" jinja templete built-in filters
syn keyword jinjaFilter contained containedin=dbtJinjaTemplate abs attr batch capitalize center default
syn keyword jinjaFilter contained containedin=dbtJinjaTemplate dictsort escape filesizeformat first
syn keyword jinjaFilter contained containedin=dbtJinjaTemplate float forceescape format groupby indent
syn keyword jinjaFilter contained containedin=dbtJinjaTemplate int join last length list lower pprint
syn keyword jinjaFilter contained containedin=dbtJinjaTemplate random replace reverse round safe slice
syn keyword jinjaFilter contained containedin=dbtJinjaTemplate sort string striptags sum
syn keyword jinjaFilter contained containedin=dbtJinjaTemplate title trim truncate upper urlize
syn keyword jinjaFilter contained containedin=dbtJinjaTemplate wordcount wordwrap

hi def link jinjaFilter Identifier

" jinja template built-in tests
syn keyword jinjaTest contained containedin=dbtJinjaTemplate callable defined divisibleby escaped
syn keyword jinjaTest contained containedin=dbtJinjaTemplate even iterable lower mapping none number
syn keyword jinjaTest contained containedin=dbtJinjaTemplate odd sameas sequence string undefined upper

hi def link jinjaTest Type

syn keyword jinjaFunction contained containedin=dbtJinjaTemplate range lipsum dict cycler joiner
hi def link jinjaFunction Function

" Keywords to highlight within comments
syn keyword jinjaTodo contained TODO FIXME XXX
syn region jinjaComBlock start="{#" end="#}" contains=jinjaTodo containedin=ALLBUT,@jinjaBlocks

hi def link jinjaTodo Todo
hi def link jinjaComBlock Comment


" ---------------------------
" Additional dbt Jinja syntax
" These are specific to SQL files that have embedded Jinja in them
" ---------------------------

" Common dbt Jinja syntax

" Common dbt functions as well package imported functions, e.g.
" dbt_utils.foo(..)
syn keyword dbtJinjaFunction    ref source config var   containedin=dbtJinjaTemplate
syn match   dbtJinjaFunction    "\v\S+\ze\(\_.{-}\)"      containedin=dbtJinjaTemplate
syn region  dbtJinjaString      matchgroup=Quote start=+"+ end=+"+ skipwhite keepend containedin=dbtJinjaTemplate
syn region  dbtJinjaString      matchgroup=Quote start=+'+ end=+'+ skipwhite keepend containedin=dbtJinjaTemplate

hi link     dbtJinjaOperator    Operator
hi link     dbtJinjaFunction    Function
hi link     dbtJinjaString      String

syn cluster dbtJinja           contains=dbtJinjaFunction,dbtJinjaString

syn region  dbtJinjaTemplate   matchgroup=dbtJinjaOperator start=+{%+ end=+%}+ contains=@dbtJinja,jinjaStatement,jinjaFilter,dbtJinjaTemplate transparent
syn region  dbtJinjaTemplate   matchgroup=dbtJinjaOperator start=+{{+ end=+}}+ contains=@dbtJinja,jinjaStatement,jinjaFilter,dbtJinjaTemplate transparent

" CTE name, attempts to match xxx in > xxx as ( ... )
syn match   dbtJinjaKeyword     "\v\S+\ze\s+as\s+\(\_.{-}\)"
syn keyword dbtJinjaKeyword     this containedin=dbtJinjaTemplate
hi  link    dbtJinjaKeyword     PreProc

let b:current_syntax = "dbt"
