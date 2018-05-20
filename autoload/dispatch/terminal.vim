" dispatch.vim terminal strategy

if exists('g:autoloaded_dispatch_terminal')
  finish
endif
let g:autoloaded_dispatch_terminal = 1

if !exists('s:waiting')
  let s:waiting = {}
endif

function! dispatch#terminal#handle(request) abort
  if !get(g:, 'dispatch_experimental', 1)
    return 0
  endif
  if !has('terminal') || a:request.action !=# 'start'
    return 0
  endif

  call dispatch#autowrite()

  let options = {
        \ 'exit_cb': function('s:exit'),
        \ 'hidden': 1,
        \ 'term_rows': get(g:, 'dispatch_quickfix_height', 10),
        \ 'term_name': a:request.title,
        \ 'term_finish': (a:request.background ? 'open' : 'close'),
        \ }
  let buf_id = term_start([&shell, &shellcmdflag, a:request.expanded], options)
  silent exec 'tab sbuffer ' . buf_id
  if !a:request.background | wincmd p | endif

  let job = term_getjob(buf_id)
  let a:request.pid = job_info(job).process
  let pid = job_info(job).process
  let s:waiting[pid] = a:request
  call writefile([a:request.pid], a:request.file . '.pid')
  let a:request.handler = 'terminal'

  return 1
endfunction

function! s:exit(job, status) abort
  let pid = job_info(a:job).process
  let request = s:waiting[pid]
  call writefile([a:status], request.file . '.complete')
  unlet! s:waiting[pid]
endfunction

function! dispatch#terminal#activate(pid) abort
  if index(keys(s:waiting), a:pid) >= 0
    let request = s:waiting[a:pid]
    let buf_id = bufnr(request.title)
    let [opened_tab, opened_window] = s:find_open_window(buf_id)

    if buf_id && opened_tab
      silent exec ':tabnext ' . opened_tab

      if opened_window
        silent exec opened_window . 'wincmd w'
      endif

      return 1
    elseif buf_id
      silent exec 'tab sbuffer ' . buf_id
      return 1
    else
      return 0
    endif
  endif

  return 0
endfunction

function! s:find_open_window(buffer_id)
   let [current_tab, last_tab] = [tabpagenr() - 1, tabpagenr('$')]

   for tab_offset in range(0, tabpagenr('$') - 1)
     let tab_id = (current_tab + tab_offset) % last_tab + 1
     let buffers = tabpagebuflist(tab_id)

     for window_id in range(1, len(buffers))
       let buffer = buffers[window_id - 1]

       if buffer == a:buffer_id
         return [tab_id, window_id]
       endif
     endfor
   endfor

   return [0, 0]
 endfunction
