" Vim syntax file
" Language:           Braid (A PowerShell Language)
" Maintainer:         Bruce Payette
" Version:            0.1
" Project Repository: https://github.com/brucepay
" Vim Script Page:    http://www.vim.org/scripts/
"
" The following settings are available for tuning syntax highlighting:
"    let braid_nofold_blocks = 1
"    let braid_nofold_region = 1

" Compatible VIM syntax file start
if version < 600
	syntax clear
elseif exists("b:current_syntax")
	finish
endif

" Operators contain dashes
setlocal iskeyword+=-

" Braid doesn't care about case
syn case ignore

" Sync-ing method
syn sync minlines=100

" Certain tokens can't appear at the top level of the document
syn cluster braidNotTop contains=@braidComment,braidCDocParam,braidFunctionDeclaration

" Comments and special comment words
syn keyword braidCommentTodo  TODO FIXME XXX TBD HACK NOTE BUGBUG BUGBUGBUG contained
syn match braidComment        /(;.*;)\|;.*/ contains=braidCommentTodo,braidCommentDoc,@Spell

" Language keywords and elements
syn keyword braidKeyword     if when unless while for foreach forall cond let const do def defn def-special def-macro fn
syn keyword braidKeyword     lambda quote repeat repeat-all load flatmap map reduce filter void vector? some? null? zero? 
syn keyword braidKeyword     const try -catch: -finally: throw return zip void join alert warn info println print
syn keyword braidKeyword     cons vcons nconc union intersect except reduce reduce-with-seed undef tuple type-alias throw
syn keyword braidKeyword     tailcall tail swap sleep skip skip-while set-assoc rol reverse return rest fmt flatten

syn keyword braidConstant    true false null nil _  IsLinux IsMacOS IsWindows IsCoreCLR IsUnix tid 


" Variable references
syn match braidVariable      /\w\+/ 

" Type literals
syn match braidType /\^[a-z_][a-z0-9_.,\[\]]*/

" braid Operators
syn keyword braidOperator is? as number? list? nil? null? lambda? atom? symbol? string? bound? dict?
syn keyword braidOperator keyword? pair? quote? zero? band bor not and or
syn match braidOperator /[a-z_][._a-z0-9]*\/[a-z_][a-z0-9_]*/
syn match braidOperator /\./
syn match braidOperator /=/
syn match braidOperator /+/
syn match braidOperator /\*/
syn match braidOperator /\*\*/
syn match braidOperator /\//
syn match braidOperator /|/
syn match braidOperator /%/
syn match braidOperator /,/
syn match braidOperator /\./
syn match braidOperator /\.\./
syn match braidOperator /</
syn match braidOperator /<=/
syn match braidOperator />/
syn match braidOperator />=/
syn match braidOperator /==/
syn match braidOperator /!=/
syn match braidOperator /->/
syn match braidOperator /\.[a-z_][._a-z0-9]*/
syn match braidOperator /\.[a-z_][._a-z0-9]*\/[a-z_][a-z0-9_]*/
syn match braidOperator /?\[/
syn match braidOperator /\~/
syn match braidOperator /\[/
syn match braidOperator /\]/
syn match braidOperator /(/
syn match braidOperator /)/


" Regular expression literals
syn region braidString start=/#"/ skip=/\\"/ end=/"/

" Strings
syn region braidString start=/"/ skip=/\\"/ end=/"/ contains=@Spell
syn region braidString start=/"""/ end=/"""/ contains=@Spell


" Interpolation in strings
syn region braidInterpolation matchgroup=braidInterpolationDelimiter start="${" end="}" contained contains=ALLBUT,@braidNotTop
syn region braidNestedParentheses start="(" skip="\\\\\|\\)" matchgroup=braidInterpolation end=")" transparent contained
syn cluster braidStringSpecial contains=braidEscape,braidInterpolation,braidVariable,braidBoolean,braidConstant,braidBuiltIn,@Spell

" Numbers
syn match   braidNumber		"\(\<\|-\)\@<=\(0[xX]\x\+\|\d\+\)\([KMGTP][B]\)\=\(\>\|-\)\@="
syn match   braidNumber		"\(\(\<\|-\)\@<=\d\+\.\d*\|\.\d\+\)\([eE][-+]\=\d\+\)\=[dD]\="
syn match   braidNumber		"\<\d\+[eE][-+]\=\d\+[dD]\=\>"
syn match   braidNumber		"\<\d\+\([eE][-+]\=\d\+\)\=[dD]\>"
syn match   braidNumber      "\<\d\+i\>" " bigint constants

" Constants
syn match braidBoolean        "\%(true\|false\)\>"
syn match braidConstant       /\nil\>/

" Folding blocks
if !exists('g:braid_nofold_blocks')
	syn region braidBlock start=/(/ end=/)/ transparent fold
endif

if !exists('g:braid_nofold_region')
	syn region braidRegion start=/;region/ end=/;endregion/ transparent fold keepend extend
endif

" Setup default color highlighting
if version >= 508 || !exists("did_braid_syn_inits")

    if version < 508
		let did_braid_syn_inits = 1
		command -nargs=+ HiLink hi link <args>
	else
		command -nargs=+ HiLink hi def link <args>
	endif

	HiLink braidNumber Number
	HiLink braidBlock Block
	HiLink braidRegion Region
	HiLink braidException Exception
	HiLink braidConstant Constant
	HiLink braidString String
	HiLink braidEscape SpecialChar
	HiLink braidInterpolationDelimiter Delimiter
	HiLink braidConditional Conditional
	HiLink braidFunctionDeclaration Function
	HiLink braidFunctionInvocation Function
	HiLink braidVariable Identifier
	HiLink braidBoolean Boolean
	HiLink braidConstant Constant
	HiLink braidBuiltIn StorageClass
	HiLink braidType Type
	HiLink braidComment Comment
	HiLink braidCommentTodo Todo
	HiLink braidCommentDoc Tag
	HiLink braidCDocParam Todo
	HiLink braidOperator Operator
	HiLink braidRepeat Repeat
	HiLink braidRepeatAndCmdlet Repeat
	HiLink braidKeyword Keyword
endif

let b:current_syntax = "braid"
