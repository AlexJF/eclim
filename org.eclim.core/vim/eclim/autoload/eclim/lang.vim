" Author:  Eric Van Dewoestine
"
" Description: {{{
"   Common language functionality (validation, completion, etc.) abstracted
"   into re-usable functions.
"
" License:
"
" Copyright (C) 2005 - 2011  Eric Van Dewoestine
"
" This program is free software: you can redistribute it and/or modify
" it under the terms of the GNU General Public License as published by
" the Free Software Foundation, either version 3 of the License, or
" (at your option) any later version.
"
" This program is distributed in the hope that it will be useful,
" but WITHOUT ANY WARRANTY; without even the implied warranty of
" MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
" GNU General Public License for more details.
"
" You should have received a copy of the GNU General Public License
" along with this program.  If not, see <http://www.gnu.org/licenses/>.
"
" }}}

" Script Variables {{{
  let s:update_command = '-command <lang>_src_update -p "<project>" -f "<file>"'
  let s:validate_command = '-command <type>_validate -p "<project>" -f "<file>"'
" }}}

" CodeComplete(command, findstart, base, [options]) {{{
" Handles code completion.
function! eclim#lang#CodeComplete(command, findstart, base, ...)
  if a:findstart
    " update the file before vim makes any changes.
    call eclim#util#ExecWithoutAutocmds('silent update')

    if !eclim#project#util#IsCurrentFileInProject(0) || !filereadable(expand('%'))
      return -1
    endif

    " locate the start of the word
    let line = getline('.')

    let start = col('.') - 1

    "exceptions that break the rule
    if line[start] =~ '\.'
      let start -= 1
    endif

    while start > 0 && line[start - 1] =~ '\w'
      let start -= 1
    endwhile

    return start
  else
    if !eclim#project#util#IsCurrentFileInProject(0) || !filereadable(expand('%'))
      return []
    endif

    let offset = eclim#util#GetOffset() + len(a:base)
    let project = eclim#project#util#GetCurrentProjectName()
    let file = eclim#project#util#GetProjectRelativeFilePath()

    let command = a:command
    let command = substitute(command, '<project>', project, '')
    let command = substitute(command, '<file>', file, '')
    let command = substitute(command, '<offset>', offset, '')
    let command = substitute(command, '<encoding>', eclim#util#GetEncoding(), '')
    if a:0
      let options = a:1
      if has_key(options, 'layout')
        let command = substitute(command, '<layout>', options.layout, '')
      endif
    endif

    let completions = []
    let results = eclim#ExecuteEclim(command)
    if type(results) != 3
      return
    endif

    let open_paren = getline('.') =~ '\%' . col('.') . 'c\s*('
    let close_paren = getline('.') =~ '\%' . col('.') . 'c\s*(\s*)'

    for result in results
      let word = result.completion

      " strip off close paren if necessary.
      if word =~ ')$' && close_paren
        let word = strpart(word, 0, strlen(word) - 1)
      endif

      " strip off open paren if necessary.
      if word =~ '($' && open_paren
        let word = strpart(word, 0, strlen(word) - 1)
      endif

      let menu = eclim#html#util#HtmlToText(result.menu)
      let info = has_key(result, 'info') ?
        \ eclim#html#util#HtmlToText(result.info) : ''

      let dict = {
          \ 'word': word,
          \ 'menu': menu,
          \ 'info': info,
          \ 'dup': 1
        \ }

      call add(completions, dict)
    endfor

    return completions
  endif
endfunction " }}}

" Search(command, singleResultAction, argline) {{{
" Executes a search.
function! eclim#lang#Search(command, singleResultAction, argline)
  let argline = a:argline
  "if argline == ''
  "  call eclim#util#EchoError('You must supply a search pattern.')
  "  return
  "endif

  " check if pattern supplied without -p.
  if argline !~ '^\s*-[a-z]' && argline !~ '^\s*$'
    let argline = '-p ' . argline
  endif

  if !eclim#project#util#IsCurrentFileInProject(0)
    let args = eclim#util#ParseArgs(argline)
    let index = index(args, '-s') + 1
    if index && len(args) > index && args[index] != 'all'
      return
    endif
    let argline .= ' -s all'
  endif

  let search_cmd = a:command
  let project = eclim#project#util#GetCurrentProjectName()
  if project != ''
    let search_cmd .= ' -n "' . project . '"'
  endif

  " no pattern supplied, use element search.
  if argline !~ '-p\>'
    if !eclim#project#util#IsCurrentFileInProject(1)
      return
    endif
    " update the file.
    call eclim#util#ExecWithoutAutocmds('silent update')

    let file = eclim#project#util#GetProjectRelativeFilePath()
    let position = eclim#util#GetCurrentElementPosition()
    let offset = substitute(position, '\(.*\);\(.*\)', '\1', '')
    let length = substitute(position, '\(.*\);\(.*\)', '\2', '')
    let encoding = eclim#util#GetEncoding()
    let search_cmd .= ' -f "' . file . '"' .
      \ ' -o ' . offset . ' -l ' . length . ' -e ' . encoding
  else
    " quote the search pattern
    let search_cmd = substitute(
      \ search_cmd, '\(.*-p\s\+\)\(.\{-}\)\(\s\|$\)\(.*\)', '\1"\2"\3\4', '')
  endif

  let search_cmd .= ' ' . argline

  let workspace = eclim#eclipse#ChooseWorkspace()
  if workspace == '0'
    return ''
  endif

  let port = eclim#client#nailgun#GetNgPort(workspace)
  let results =  eclim#ExecuteEclim(search_cmd, port)
  if type(results) != 3
    return
  endif

  if !empty(results)
    call eclim#util#SetLocationList(eclim#util#ParseLocationEntries(results))
    " if only one result and it's for the current file, just jump to it.
    " note: on windows the expand result must be escaped
    if len(results) == 1 && results[0].filename =~ escape(expand('%:p'), '\') . '|'
      if results[0].line != 1 && results[0].column != 1
        lfirst
      endif

    " single result in another file.
    elseif len(results) == 1 && a:singleResultAction != "lopen"
      let entry = getloclist(0)[0]
      call eclim#util#GoToBufferWindowOrOpen
        \ (bufname(entry.bufnr), a:singleResultAction)
      call eclim#util#SetLocationList(eclim#util#ParseLocationEntries(results))
      call eclim#display#signs#Update()

      call cursor(entry.lnum, entry.col)
    else
      lopen
    endif
    return 1
  else
    if argline !~ '-p\>'
      call eclim#util#EchoInfo("Element not found.")
    else
      let searchedFor = substitute(argline, '.*-p \(.\{-}\)\( .*\|$\)', '\1', '')
      call eclim#util#EchoInfo("Pattern '" . searchedFor . "' not found.")
    endif
  endif

endfunction " }}}

" UpdateSrcFile(validate) {{{
" Updates the src file on the server w/ the changes made to the current file.
function! eclim#lang#UpdateSrcFile(lang, validate)
  let project = eclim#project#util#GetCurrentProjectName()
  if project != ""
    let file = eclim#project#util#GetProjectRelativeFilePath()
    let command = s:update_command
    let command = substitute(command, '<lang>', a:lang, '')
    let command = substitute(command, '<project>', project, '')
    let command = substitute(command, '<file>', file, '')
    if a:validate && !eclim#util#WillWrittenBufferClose()
      let command = command . ' -v'
      if eclim#project#problems#IsProblemsList()
        let command = command . ' -b'
      endif
    endif

    let result = eclim#ExecuteEclim(command)
    if type(result) == g:LIST_TYPE && len(result) > 0
      let errors = eclim#util#ParseLocationEntries(
        \ result, g:EclimValidateSortResults)
      call eclim#util#SetLocationList(errors)
    else
      call eclim#util#ClearLocationList('global')
    endif

    call eclim#project#problems#ProblemsUpdate()
  elseif a:validate && expand('<amatch>') == ''
    call eclim#project#util#IsCurrentFileInProject()
  endif
endfunction " }}}

" Validate(type, on_save) {{{
" Validates the current file. Used by languages which are not validated via
" UpdateSrcFile (pretty much all the xml dialects and wst langs).
function! eclim#lang#Validate(type, on_save)
  if eclim#util#WillWrittenBufferClose()
    return
  endif

  if !eclim#project#util#IsCurrentFileInProject(!a:on_save)
    return
  endif

  let project = eclim#project#util#GetCurrentProjectName()
  let file = eclim#project#util#GetProjectRelativeFilePath()
  let command = s:validate_command
  let command = substitute(command, '<type>', a:type, '')
  let command = substitute(command, '<project>', project, '')
  let command = substitute(command, '<file>', file, '')

  let result = eclim#ExecuteEclim(command)
  if type(result) == g:LIST_TYPE && len(result) > 0
    let errors = eclim#util#ParseLocationEntries(
      \ result, g:EclimValidateSortResults)
    call eclim#util#SetLocationList(errors)
  else
    call eclim#util#ClearLocationList()
  endif
endfunction " }}}

" SilentUpdate() {{{
" Silently updates the current source file w/out validation.
function! eclim#lang#SilentUpdate()
  " i couldn't reproduce the issue, but at least one person experienced the
  " cursor moving on update and breaking code completion:
  " http://sourceforge.net/tracker/index.php?func=detail&aid=1995319&group_id=145869&atid=763323
  let pos = getpos('.')

  try
    silent noautocmd update
  finally
    call setpos('.', pos)
  endtry
endfunction " }}}

" vim:ft=vim:fdm=marker
