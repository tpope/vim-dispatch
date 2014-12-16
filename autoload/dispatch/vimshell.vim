" dispatch.vim vimshell strategy

if exists('g:autoloaded_dispatch_vimshell')
  finish
endif
let g:autoloaded_dispatch_vimshell = 1

function! dispatch#vimshell#handle(request) abort
  if !exists('g:loaded_vimshell') || a:request.background
    return 0
  endif

  let s:tempfile = a:request.file
  let s:action = a:request.action

  let vimshell_context = {
        \ 'buffer_name': 'vim-dispatch',
        \ 'create': 1,
        \ 'prompt': '$ '
        \ }

  if s:action ==# 'make'
    let vimshell_context.split = 1
    let vimshell_context.split_command = 'botright split | resize 10'
  elseif s:action ==# 'start'
    let vimshell_context.tab = 1
    execute 'tabnew'
  endif

  call vimshell#init#_start(a:request.directory, vimshell_context)
  call vimshell#hook#add('preparse', 'dispatch', 'dispatch#vimshell#preparse')

  if s:action ==# 'make'
    call vimshell#hook#add('postexit', 'dispatch', 'dispatch#vimshell#postexit')
    execute 'wincmd p'
  endif

  let a:request.pid = bufnr('%')
  let s:pid = a:request.pid

  call vimshell#interactive#send(a:request.expanded)

  return 1
endfunction

function! dispatch#vimshell#activate(pid) abort
  for tabpage in range(tabpagenr('$'))
    let tabnumber = tabpage + 1
    for bufnr in tabpagebuflist(tabnumber)
      if bufnr ==# a:pid
        execute 'tabnext '.tabnumber
        execute bufwinnr(bufnr).'wincmd w'

        return 1
      endif
    endfor
  endfor
endfunction

function! dispatch#vimshell#running(pid) abort
  return bufexists(str2nr(a:pid))
endfunction

function! dispatch#vimshell#preparse(...) abort
  call vimshell#hook#remove('preparse', 'dispatch')

  setlocal norelativenumber
  setlocal nonumber

  let command = a:1

  if s:action ==# 'make'
    let s:updatetime = &updatetime
    let &updatetime = 100
    let command .= ' '.&shellpipe.' '.s:tempfile
  endif

  return 'clear; '.
        \ 'echo '.s:pid.' > '.s:tempfile.'.pid; '.
        \ &shell.' '.&shellcmdflag.' '.vimproc#shellescape(command).
        \ '; exit'
endfunction

function! dispatch#vimshell#postexit(...) abort
  call vimshell#hook#remove('postexit', 'dispatch')
  let &updatetime = s:updatetime

  call system(&shell.' '.&shellcmdflag.' '.
        \ shellescape("perl -pi.bak -e 's/\x1b.*?[mGKH]//g' ".s:tempfile))
  call dispatch#copen(0)
  execute 'wincmd p'
endfunction
