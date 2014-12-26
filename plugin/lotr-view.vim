"" ============================================================================
" File:        lotr-view.vim
" Description: A persistent view of :registers in Vim
" Authors:     Barry Arthur <barry.arthur@gmail.com>
" Licence:     Vim licence
" Website:     http://dahu.github.com/vim-lotr/
" Version:     0.1
" Note:        This plugin was heavily inspired by the 'Tagbar' plugin by
"              Jan Larres and uses great gobs of code from it.
"
" Original taglist copyright notice:
"              Permission is hereby granted to use and distribute this code,
"              with or without modifications, provided that this copyright
"              notice is copied with it. Like anything else that's free,
"              taglist.vim is provided *as is* and comes with no warranty of
"              any kind, either expressed or implied. In no event will the
"              copyright holder be liable for any damamges resulting from the
"              use of this software.
" ============================================================================

if &cp || exists('g:loaded_lotr')
  finish
endif

" Initialization {{{1

" Basic init {{{2

if v:version < 700
  echomsg 'LOTR: Vim version is too old, LOTR requires at least 7.0'
  finish
endif

redir => s:ftype_out
silent filetype
redir END
if s:ftype_out !~# 'detection:ON'
  echomsg 'LOTR: Filetype detection is turned off, skipping plugin'
  unlet s:ftype_out
  finish
endif
unlet s:ftype_out

let g:loaded_lotr = 1

if !exists('g:lotr_left')
  let g:lotr_left = 0
endif

if !exists('g:lotr_width')
  let g:lotr_width = 20
endif

if !exists('g:lotr_compact')
    let g:lotr_compact = 0
endif

if !exists('g:lotr_minify')
    let g:lotr_minify = 1
endif

if !exists('g:lotr_expand')
  let g:lotr_expand = 0
endif

let s:autocommands_done        = 0
let s:source_autocommands_done = 0
let s:window_expanded          = 0


" local data structure for registers

function! CleoMarks(cursor_line)
  let marks = g:vimple#ma.update().local_marks().to_l()
  " Locate the cursor line within the marks
  " 1. does it fall on a mark?
  call map(marks, 'v:val["line"] == ' . a:cursor_line . ' ? extend(v:val, {"cursor" : ""}) : v:val')
  if len(filter(copy(marks), 'has_key(v:val, "cursor")')) == 0
    " 2. where does it fall between marks?
    " 0  == before all marks
    " -1 == after all marks
    " positive integer == the index of the cursor line
    if len(marks) == 0
      let cursor_index = 0
    else
      let cursor_index = index(map(sort(map(copy(marks), 'v:val["line"]'), 'Numerically'),
            \ 'v:val == min([v:val,' . a:cursor_line . '])'), 0)
    endif
    call insert(marks,
          \ {'cursor' : '', 'line' : a:cursor_line, 'mark' : '', 'text' : ''},
          \ cursor_index)
  endif
  return map(sort(marks, 'Linely'),
        \ 'printf("%1s %3s %4d %s", has_key(v:val, "cursor") ? "*" : "",
        \ CleoMarkHiercharchy(v:val["mark"]),
        \ v:val["line"], s:MinifyText(v:val["text"]))')
endfunction

function! s:MinifyText(text)
  if g:lotr_minify
    return strpart(a:text, 0, (&columns - 3))
  else
    return a:text
  endif
endfunction

function! s:CreateAutocommands() "{{{2
  augroup LOTR_AutoCmds
    autocmd!
    autocmd BufEnter    __LOTR__  nested call s:QuitIfOnlyWindow()
    autocmd BufUnload   __LOTR__         call s:CleanUp()
    " autocmd CursorMoved __LOTR__         call s:AutoUpdate()
  augroup END

  let s:autocommands_done = 1
endfunction

function! s:CreateSourceAutocommands() "{{{2
  augroup LOTR_SourceAutoCmds
    autocmd!
    autocmd CursorMoved <buffer> call s:SourceAutoUpdate()
  augroup END
  let s:source_autocommands_done = 1
endfunction


function! s:MapKeys() "{{{2
  nnoremap <script> <silent> <buffer> <CR> :wincmd p<cr>
  nnoremap <script> <silent> <buffer> m    :call <SID>ToggleMinify()<CR>
  nnoremap <script> <silent> <buffer> q    :call <SID>CloseWindow()<CR>
endfunction

" TODO: Currently only reflects toggle after leaving & entering LOTR window
function! s:ToggleMinify()
  let g:lotr_minify = !g:lotr_minify
  call s:RenderContent()
endfunction


" Window management {{{1
" Window management code shamelessly stolen from the Tagbar plugin:
" http://www.vim.org/scripts/script.php?script_id=3465

function! s:ToggleWindow() "{{{2
  let lotr_winnr = bufwinnr("__LOTR__")
  if lotr_winnr != -1
    call s:CloseWindow()
    return
  endif

  call s:OpenWindow(0)
endfunction


function! s:OpenWindow(autoclose) "{{{2
  " If the LOTR window is already open jump to it
  let lotr_winnr = bufwinnr('__LOTR__')
  if lotr_winnr != -1
    if winnr() != lotr_winnr
      let s:lotr_regs = LOTR_Regs()
      execute lotr_winnr . 'wincmd w'
    endif
    return
  else
    let s:lotr_regs = LOTR_Regs()
  endif

  " Expand the Vim window to accomodate for the LOTR window if requested
  if g:lotr__expand && !s:window_expanded && has('gui_running')
    let &columns += g:lotr__width + 1
    let s:window_expanded = 1
  endif

  let openpos = g:lotr__left ? 'topleft vertical ' : 'botright vertical '
  exe 'silent keepalt ' . openpos . g:lotr__width . 'split ' . '__LOTR__'
  call s:InitWindow(a:autoclose)

  execute 'wincmd p'

  " TODO: need a better name for this, or a better way to do it
  if !s:source_autocommands_done
    call s:CreateSourceAutocommands()
  endif
endfunction


function! s:InitWindow(autoclose) "{{{2
  setlocal noreadonly " in case the "view" mode is used
  setlocal buftype=nofile
  setlocal bufhidden=hide
  setlocal noswapfile
  setlocal nobuflisted
  setlocal nomodifiable
  setlocal filetype=lotr
  setlocal nolist
  setlocal nonumber
  setlocal nowrap
  setlocal winfixwidth
  setlocal textwidth=0

  if exists('+relativenumber')
    setlocal norelativenumber
  endif

  setlocal nofoldenable
  setlocal foldcolumn=0
  " Reset fold settings in case a plugin set them globally to something
  " expensive. Apparently 'foldexpr' gets executed even if 'foldenable' is
  " off, and then for every appended line (like with :put).
  setlocal foldmethod&
  setlocal foldexpr&

  " Script-local variable needed since compare functions can't
  " take extra arguments
  let s:compare_typeinfo = {}

  let s:is_maximized = 0

  let w:autoclose = a:autoclose

  let cpoptions_save = &cpoptions
  set cpoptions&vim

  if !hasmapto('CloseWindow', 'n')
    call s:MapKeys()
  endif

  if !s:autocommands_done
    call s:CreateAutocommands()
  endif

  call s:RenderContent()

  let &cpoptions = cpoptions_save
endfunction

function! s:CloseWindow() "{{{2
  let lotr_winnr = bufwinnr('__LOTR__')
  if lotr_winnr == -1
    return
  endif

  let lotr_bufnr = winbufnr(lotr_winnr)

  if winnr() == lotr_winnr
    if winbufnr(2) != -1
      " Other windows are open, only close the LOTR one
      close
    endif
  else
    " Go to the LOTR window, close it and then come back to the
    " original window
    let curbufnr = bufnr('%')
    execute lotr_winnr . 'wincmd w'
    close
    " Need to jump back to the original window only if we are not
    " already in that window
    let winnum = bufwinnr(curbufnr)
    if winnr() != winnum
      exe winnum . 'wincmd w'
    endif
  endif

  " If the Vim window has been expanded, and LOTR is not open in any other
  " tabpages, shrink the window again
  if s:window_expanded
    let tablist = []
    for i in range(tabpagenr('$'))
      call extend(tablist, tabpagebuflist(i + 1))
    endfor

    if index(tablist, lotr_bufnr) == -1
      let &columns -= g:lotr__width + 1
      let s:window_expanded = 0
    endif
  endif
endfunction

function! s:ZoomWindow() "{{{2
  if s:is_maximized
    execute 'vert resize ' . g:lotr_width
    let s:is_maximized = 0
  else
    vert resize
    let s:is_maximized = 1
  endif
endfunction


" Display {{{1
function! s:RenderContent() "{{{2
  " only update the LOTR window if we're in normal mode
  if mode(1) != 'n'
    return
  endif
  let lotr_winnr = bufwinnr('__LOTR__')

  if &filetype == 'lotr'
    let in_lotr = 1
  else
    let in_lotr = 0
    let s:lotr_regs = LOTR_Regs()
    let prevwinnr = winnr()
    execute lotr_winnr . 'wincmd w'
  endif

  let lazyredraw_save = &lazyredraw
  set lazyredraw
  let eventignore_save = &eventignore
  set eventignore=all

  setlocal modifiable

  silent %delete _

  call s:PrintRegs()

  setlocal nomodifiable

  let &lazyredraw  = lazyredraw_save
  let &eventignore = eventignore_save

  if !in_lotr
    execute prevwinnr . 'wincmd w'
  endif
endfunction

function! s:PrintRegs() "{{{2
  call setline(1, s:lotr_regs)
endfunction

" User Actions {{{1

" Helper Functions {{{1

" s:CleanUp() {{{2
function! s:CleanUp()
  silent autocmd! LOTRAutoCmds

  unlet s:is_maximized
  unlet s:compare_typeinfo
endfunction

" s:QuitIfOnlyWindow() {{{2
function! s:QuitIfOnlyWindow()
  " Before quitting Vim, delete the LOTR buffer so that
  " the '0 mark is correctly set to the previous buffer.
  if winbufnr(2) == -1
    " Check if there is more than one tab page
    if tabpagenr('$') == 1
      bdelete
      quit
    else
      close
    endif
  endif
endfunction

function! s:AutoUpdate() " {{{2
  " Don't do anything if LOTR is not open or if we're in the LOTR window
  let lotr_winnr = bufwinnr('__LOTR__')
  if lotr_winnr == -1
    return
  endif
  if &filetype == 'lotr'
    let line = getline('.')
    let line_num = matchstr(line, ' \zs\d\+')
    wincmd p
    exe 'normal ' . line_num . 'Gzz'
    redraw
    wincmd p
  else
    call s:RenderContent()
  endif
endfunction

function! s:SourceAutoUpdate() "{{{2
  " Don't do anything if LOTR is not open or if we're in the LOTR window
  let lotr_winnr = bufwinnr('__LOTR__')
  if lotr_winnr == -1 || &filetype == 'lotr_'
    return
  endif

  call s:RenderContent()
endfunction

" Maps {{{1
nnoremap <leader>cr :LOTRToggle<CR>:wincmd p<CR>

" Commands {{{1
command! -nargs=0 LOTRToggle        call s:ToggleWindow()
command! -nargs=0 LOTROpen          call s:OpenWindow(0)
command! -nargs=0 LOTROpenAutoClose call s:OpenWindow(1)
command! -nargs=0 LOTRClose         call s:CloseWindow()

" Modeline {{{1
" vim: ts=8 sw=2 sts=2 et foldenable foldmethod=marker foldcolumn=1
