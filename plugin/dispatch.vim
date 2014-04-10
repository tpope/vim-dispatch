" Location:     plugin/dispatch.vim
" Maintainer:   Tim Pope <http://tpo.pe/>
" Version:      1.1

if exists("g:loaded_dispatch") || v:version < 700 || &cp
  finish
endif
let g:loaded_dispatch = 1

command! -bang -nargs=* -range=0 -complete=custom,dispatch#command_complete Dispatch
      \ execute dispatch#compile_command(<bang>0, <q-args>, <count>)

command! -bang -nargs=* -complete=custom,dispatch#command_complete FocusDispatch
      \ execute dispatch#focus_command(<bang>0, <q-args>)

command! -bang -nargs=* -complete=file Make
      \ Dispatch<bang> _ <args>

command! -bang -nargs=* -complete=custom,dispatch#command_complete Start
      \ execute dispatch#start_command(<bang>0, <q-args>)

command! -bang -bar Copen call dispatch#copen(<bang>0)

function! DispatchComplete(id) abort
  return dispatch#complete(a:id)
endfunction

if !exists('g:dispatch_handlers')
  let g:dispatch_handlers = [
        \ 'tmux',
        \ 'screen',
        \ 'windows',
        \ 'iterm',
        \ 'x11',
        \ 'headless',
        \ ]
endif
