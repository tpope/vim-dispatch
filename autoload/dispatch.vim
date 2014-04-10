" Location:     autoload/dispatch.vim

if exists('g:autoloaded_dispatch')
  finish
endif

let g:autoloaded_dispatch = 1

" Utility {{{1

function! dispatch#uniq(list) abort
  let i = 0
  let seen = {}
  while i < len(a:list)
    if (a:list[i] ==# '' && exists('empty')) || has_key(seen,a:list[i])
      call remove(a:list,i)
    elseif a:list[i] ==# ''
      let i += 1
      let empty = 1
    else
      let seen[a:list[i]] = 1
      let i += 1
    endif
  endwhile
  return a:list
endfunction

function! dispatch#shellescape(...) abort
  let args = []
  for arg in a:000
    if arg =~ '^[A-Za-z0-9_/.-]\+$'
      let args += [arg]
    else
      let args += [shellescape(arg)]
    endif
  endfor
  return join(args, ' ')
endfunction

let s:flags = '\%(:[p8~.htre]\|:g\=s\(.\).\{-\}\1.\{-\}\1\)*'
let s:expandable = '\\*\%(<\w\+>\|%\|#\d*\)' . s:flags
function! dispatch#expand(string) abort
  return substitute(a:string, s:expandable, '\=s:expand(submatch(0))', 'g')
endfunction

function! s:expand(string) abort
  let slashes = len(matchstr(a:string, '^\%(\\\\\)*'))
  return repeat('\', slashes/2) . expand(a:string[slashes : -1])
endfunction

function! dispatch#slash() abort
  return !exists("+shellslash") || &shellslash ? '/' : '\'
endfunction

function! dispatch#shellpipe(file) abort
  if &shellpipe =~# '%s'
    return ' ' . printf(&shellpipe, dispatch#shellescape(a:file))
  else
    return ' ' . &shellpipe . ' ' . dispatch#shellescape(a:file)
  endif
endfunction

function! dispatch#vim_executable() abort
  if !exists('s:vim')
    if has('win32')
      let roots = [fnamemodify($VIMRUNTIME, ':8') . dispatch#slash(),
                  \ fnamemodify($VIM, ':8') . dispatch#slash()]
    elseif has('gui_macvim')
      let roots = [fnamemodify($VIM, ':h:h') . '/MacOS/']
    else
      let roots = [fnamemodify($VIM, ':h:h') . '/bin/']
    endif
    for root in roots
      if executable(root . v:progname)
        let s:vim = root . v:progname
        break
      endif
    endfor
    if !exists('s:vim')
      if executable(v:progname)
        let s:vim = v:progname
      else
        let s:vim = 'vim'
      endif
    endif
  endif
  return s:vim
endfunction

function! dispatch#callback(request) abort
  if !empty(v:servername) && has_key(s:request(a:request), 'id')
    return dispatch#shellescape(dispatch#vim_executable()) .
          \ ' --servername ' . dispatch#shellescape(v:servername) .
          \ ' --remote-expr "' . 'DispatchComplete(' . s:request(a:request).id . ')' . '"'
  endif
  return ''
endfunction

function! dispatch#prepare_start(request, ...) abort
  let exec = 'echo $$ > ' . a:request.file . '.pid; '
  if executable('perl')
    let exec .= 'perl -e "select(undef,undef,undef,0.1)"; '
  else
    let exec .= 'sleep 1; '
  endif
  let exec .= a:0 ? a:1 : a:request.expanded
  let callback = dispatch#callback(a:request)
  let after = 'rm -f ' . a:request.file . '.pid; ' .
        \ 'touch ' . a:request.file . '.complete' .
        \ (empty(callback) ? '' : '; ' . callback)
  if &shellpipe =~# '2>&1'
    return 'trap ' . shellescape(after) . ' EXIT INT TERM; ' . exec
  else
    " csh
    return exec . '; ' . after
  endif
endfunction

function! dispatch#prepare_make(request, ...) abort
  let exec = a:0 ? a:1 : (a:request.expanded . dispatch#shellpipe(a:request.file))
  return dispatch#prepare_start(a:request, exec, 1)
endfunction

function! dispatch#set_title(request) abort
  return dispatch#shellescape('printf',
        \ '\033]1;%s\007\033]2;%s\007',
        \ a:request.title,
        \ a:request.expanded)
endfunction

function! dispatch#isolate(keep, ...) abort
  let command = ['cd ' . shellescape(getcwd())]
  for line in split(system('env'), "\n")
    let var = matchstr(line, '^\w\+\ze=')
    if !empty(var) && var !=# '_' && index(a:keep, var) < 0
      if &shell =~# 'csh'
        let command += ['setenv '.var.' '.shellescape(eval('$'.var))]
      else
        let command += ['export '.var.'='.shellescape(eval('$'.var))]
      endif
    endif
  endfor
  let command += a:000
  let temp = tempname()
  call writefile(command, temp)
  return 'env -i ' . join(map(copy(a:keep), 'v:val."=\"$". v:val ."\" "'), '') . &shell . ' ' . temp
endfunction

function! s:set_current_compiler(name) abort
  if empty(a:name)
    unlet! b:current_compiler
  else
    let b:current_compiler = a:name
  endif
endfunction

function! s:dispatch(request) abort
  for handler in g:dispatch_handlers
    let response = call('dispatch#'.handler.'#handle', [a:request])
    if !empty(response)
      redraw
      let pid = dispatch#pid(a:request)
      echo ':!'.a:request.expanded . ' ('.handler.'/'.(pid ? pid : '?').')'
      let a:request.handler = handler
      return 1
    endif
  endfor
  return 0
endfunction

" }}}1
" :Start {{{1

function! dispatch#start_command(bang, command) abort
  let command = a:command
  if empty(command) && exists('*projectile#query_exec')
    for [root, command] in projectile#query_exec('start')
      break
    endfor
  endif
  if empty(command) && type(get(b:, 'start', [])) == type('')
    let command = b:start
  endif
  let title = matchstr(command, '-title=\zs\%(\\.\|\S\)*')
  if !empty(title)
    let command = command[strlen(title) + 8 : -1]
  endif
  let title = substitute(title, '\\\(\s\)', '\1', 'g')
  let cd = exists('*haslocaldir') && haslocaldir() ? 'lcd' : 'cd'
  let restore = ''
  try
    if exists('root')
      let restore = cd . ' ' . fnameescape(getcwd())
      exe cd fnameescape(root)
    endif
    if command =~# '^:.'
      unlet! g:dispatch_last_start
      return substitute(command, '\>', get(a:0 ? a:1 : {}, 'background', 0) ? '!' : '', '')
    endif
    if empty(command)
      let command = &shell
    endif
    call dispatch#start(command, {'background': a:bang, 'title': title})
  finally
    if exists('root')
      execute restore
    endif
  endtry
  return ''
endfunction

if !exists('g:DISPATCH_STARTS')
  let g:DISPATCH_STARTS = {}
endif

function! dispatch#start(command, ...) abort
  let request = extend({
        \ 'action': 'start',
        \ 'background': 0,
        \ 'command': a:command,
        \ 'directory': getcwd(),
        \ 'expanded': dispatch#expand(a:command),
        \ 'title': '',
        \ }, a:0 ? a:1 : {})
  let g:dispatch_last_start = request
  if empty(request.title)
    let request.title = substitute(fnamemodify(matchstr(request.command, '\%(\\.\|\S\)\+'), ':t:r'), '\\\(\s\)', '\1', 'g')
  endif
  let key = request.directory."\t".substitute(request.expanded, '\s*$', '', '')
  let i = 0
  while i < len(get(g:DISPATCH_STARTS, key, []))
    let [handler, pid] = split(g:DISPATCH_STARTS[key][i], '@')
    if !s:running(pid)
      call remove(g:DISPATCH_STARTS[key], i)
      continue
    endif
    try
      if request.background || dispatch#{handler}#activate(pid)
        let request.handler = handler
        let request.pid = pid
        return request
      endif
    catch
    endtry
    let i += 1
  endwhile
  let request.file = tempname()
  let s:files[request.file] = request
  if s:dispatch(request)
    if !has_key(g:DISPATCH_STARTS, key)
      let g:DISPATCH_STARTS[key] = []
    endif
    call add(g:DISPATCH_STARTS[key], request.handler.'@'.dispatch#pid(request))
  else
    execute '!' . request.command
  endif
  return request
endfunction

" }}}1
" :Dispatch, :Make {{{1

let g:dispatch_compilers = get(g:, 'dispatch_compilers', {})

function! dispatch#compiler_for_program(args) abort
  let remove = keys(filter(copy(g:dispatch_compilers), 'empty(v:val)'))
  let pattern = '\%('.join(map(remove, 'substitute(escape(v:val, ".*^$~[]\\"), "\\w\\zs$", " ", "")'), '\s*\|').'\)'
  let args = substitute(a:args, '\s\+', ' ', 'g')
  let args = substitute(args, '^\s*'.pattern.'*', '', '')
  for [command, plugin] in items(g:dispatch_compilers)
    if strpart(args.' ', 0, len(command)+1) ==# command.' ' && !empty(plugin)
      return plugin
    endif
  endfor
  let program = fnamemodify(matchstr(args, '\S\+'), ':t:r')
  if program ==# 'make'
    return 'make'
  endif
  let plugins = map(reverse(split(globpath(escape(&rtp, ' '), 'compiler/*.vim'), "\n")), '[fnamemodify(v:val, ":t:r"), readfile(v:val)]')
  for [plugin, lines] in plugins
    for line in lines
      let full = substitute(substitute(
            \ matchstr(line, '\<CompilerSet\s\+makeprg=\zs\a\%(\\.\|[^[:space:]"]\)*'),
            \ '\\\(.\)', '\1', 'g'),
            \ ' \=["'']\=\%(%\|\$\*\|--\w\@!\).*', '', '')
      if !empty(full) && strpart(args.' ', 0, len(full)+1) ==# full.' '
        return plugin
      endif
    endfor
  endfor
  for [plugin, lines] in plugins
    for line in lines
      if matchstr(line, '\<CompilerSet\s\+makeprg=\zs[[:alnum:]_-]\+') ==# program
        return plugin
      endif
    endfor
  endfor
  return ''
endfunction

function! dispatch#compiler_options(compiler) abort
  let current_compiler = get(b:, 'current_compiler', '')
  let makeprg = &l:makeprg
  let efm = &l:efm

  try
    if a:compiler ==# 'make'
      if &makeprg !=# 'make'
        setlocal efm&
      endif
      return {'program': 'make', 'format': &efm}
    endif
    let &l:makeprg = ''
    execute 'compiler '.fnameescape(a:compiler)
    let options = {'format': &errorformat}
    if !empty(&l:makeprg)
      let options.program = &l:makeprg
    endif
    return options
  finally
    let &l:makeprg = makeprg
    let &l:efm = efm
    call s:set_current_compiler(current_compiler)
  endtry
endfunction

function! dispatch#command_complete(A, L, P) abort
  if a:L =~# '\S\+\s\S\+\s'
    return join(map(split(glob(a:A.'*'), "\n"), 'isdirectory(v:val) ? v:val . dispatch#slash() : v:val'), "\n")
  else
    let executables = []
    for dir in split($PATH, has('win32') ? ';' : ':')
      let executables += map(split(glob(dir.'/'.a:A.'*'), "\n"), 'v:val[strlen(dir)+1 : -1]')
    endfor
    return join(sort(dispatch#uniq(executables)), "\n")
  endif
endfunction

if !exists('s:makes')
  let s:makes = []
  let s:files = {}
endif

function! dispatch#compile_command(bang, args, count) abort
  if !empty(a:args)
    let args = a:args
  else
    let args = '_'
    for vars in [b:, g:, t:, w:]
      if has_key(vars, 'dispatch') && type(vars.dispatch) == type('')
        let args = vars.dispatch
      endif
    endfor
  endif

  if args =~# '^!'
    return 'Start' . (a:bang ? '!' : '') . ' ' . args[1:-1]
  elseif args =~# '^:.'
    return (a:count ? a:count : '').substitute(args[1:-1], '\>', (a:bang ? '!' : ''), '')
  endif
  let executable = matchstr(args, '\S\+')

  let request = {
        \ 'action': 'make',
        \ 'background': a:bang,
        \ 'file': tempname(),
        \ 'format': '%+G%.%#'
        \ }

  if executable ==# '_'
    let request.args = matchstr(args, '_\s*\zs.*')
    let request.program = &makeprg
    if &makeprg =~# '\$\*'
      let request.command = substitute(&makeprg, '\$\*', request.args, 'g')
    elseif empty(request.args)
      let request.command = &makeprg
    else
      let request.command = &makeprg . ' ' . request.args
    endif
    let request.format = &errorformat
    let request.compiler = get((empty(&l:makeprg) ? g: : b:), 'current_compiler', '')
  else
    let request.compiler = dispatch#compiler_for_program(args)
    if !empty(request.compiler)
      call extend(request,dispatch#compiler_options(request.compiler))
    endif
    let request.command = args
  endif
  if a:count
    let request.command = substitute(request.command, '<lnum>'.s:flags, '\=fnamemodify(a:count, submatch(0)[6:-1])', 'g')
  else
    let request.command = substitute(request.command, '<lnum>'.s:flags, '', 'g')
  endif

  if empty(request.compiler)
    unlet request.compiler
  endif
  let request.title = get(request, 'compiler', 'make')

  if &autowrite || &autowriteall
    wall
  endif
  cclose
  let &errorfile = request.file

  try
    silent doautocmd QuickFixCmdPre dispatch
    let request.directory = getcwd()
    let request.expanded = dispatch#expand(request.command)
    call extend(s:makes, [request])
    let request.id = len(s:makes)
    let s:files[request.file] = request

    if !s:dispatch(request)
      execute 'silent !'.request.command dispatch#shellpipe(request.file)
      call feedkeys(":redraw!|call dispatch#complete(".request.id.")\r", 'n')
    endif
  finally
    silent doautocmd QuickFixCmdPost dispatch
  endtry
  return ''
endfunction

" }}}1
" :FocusDispatch {{{1

function! dispatch#focus() abort
  if exists('w:dispatch')
    let [compiler, why] = [w:dispatch, 'Window local focus']
  elseif exists('t:dispatch')
    let [compiler, why] = [t:dispatch, 'Tab local focus']
  elseif exists('g:dispatch')
    let [compiler, why] = [g:dispatch, 'Global focus']
  elseif exists('b:dispatch')
    let [compiler, why] = [b:dispatch, 'Buffer default']
  elseif !empty(&l:makeprg)
    return [':Make', 'Buffer default']
  else
    return [':Make', 'Global default']
  endif
  if compiler =~# '^_\>'
    return [':Make' . compiler[1:-1], why]
  elseif compiler =~# '^!'
    return [':Start ' . compiler[1:-1], why]
  elseif compiler =~# '^:.'
    return [compiler, why]
  else
    return [':Dispatch ' . compiler, why]
  endif
endfunction

function! dispatch#focus_command(bang, args) abort
  let args = a:args =~# '^:.' ? a:args : escape(dispatch#expand(a:args), '#%')
  if empty(a:args) && a:bang
    unlet! w:dispatch t:dispatch g:dispatch
    let [what, why] = dispatch#focus()
    echo 'Reverted default to ' . what
  elseif empty(a:args)
    let [what, why] = dispatch#focus()
    echo printf('%s is %s', why, what)
  elseif a:bang
    let w:dispatch = args
    let [what, why] = dispatch#focus()
    echo 'Set window local focus to ' . what
  else
    unlet! w:dispatch t:dispatch
    let g:dispatch = args
    let [what, why] = dispatch#focus()
    echo 'Set global focus to ' . what
  endif
  return ''
endfunction

" }}}1
" Requests {{{1

function! s:file(request) abort
  if type(a:request) == type('')
    return a:request
  elseif type(a:request) == type({})
    return get(a:request, 'file', '')
  else
    return get(get(s:makes, a:request-1, {}), 'file', '')
  endif
endfunction

function! s:request(request) abort
  if type(a:request) == type({})
    return a:request
  elseif type(a:request) == type(0) && a:request > 0
    return get(s:makes, a:request-1, {})
  elseif type(a:request) == type('') && !empty(a:request)
    return get(s:files, a:request, {})
  else
    return {}
  endif
endfunction

function! dispatch#request(...) abort
  return a:0 ? s:request(a:1) : get(s:makes, -1, {})
endfunction

function! s:running(pid) abort
  if !a:pid
    return 0
  elseif has('win32')
    return system('tasklist /fi "pid eq '.a:pid.'"') =~# '==='
  else
    call system('kill -0 '.a:pid)
    return !v:shell_error
  endif
endfunction

function! dispatch#pid(request) abort
  let request = s:request(a:request)
  let file = request.file
  if !has_key(request, 'pid')
    if has('win32') && !executable('wmic')
      let request.pid = 0
      return 0
    endif
    for i in range(50)
      if getfsize(file.'.pid') > 0 || filereadable(file.'.complete')
        break
      endif
      sleep 10m
    endfor
    try
      let request.pid = +readfile(file.'.pid')[0]
    catch
      let request.pid = 0
    endtry
  endif
  if request.pid && getfsize(file.'.pid') > 0
    if s:running(request.pid)
      return request.pid
    else
      let request.pid = 0
      call delete(file)
    endif
  endif
endfunction

function! dispatch#completed(request) abort
  return get(s:request(a:request), 'completed', 0)
endfunction

function! dispatch#complete(file) abort
  if !dispatch#completed(a:file)
    let request = s:request(a:file)
    let request.completed = 1
    echo 'Finished:' request.command
    if !request.background
      call s:cgetfile(request, 0, 0)
      redraw
    endif
  endif
  return ''
endfunction

" }}}1
" Quickfix window {{{1

function! dispatch#copen(bang) abort
  if empty(s:makes)
    return 'echoerr ' . string('No dispatches yet')
  endif
  let request = s:makes[-1]
  if !dispatch#completed(request) && filereadable(request.file . '.complete')
    let request.completed = 1
  endif
  call s:cgetfile(request, a:bang, 1)
endfunction

function! s:cgetfile(request, all, copen) abort
  let request = s:request(a:request)
  let efm = &l:efm
  let makeprg = &l:makeprg
  let compiler = get(b:, 'current_compiler', '')
  let cd = haslocaldir() ? 'lcd' : 'cd'
  let dir = getcwd()
  try
    call s:set_current_compiler(get(request, 'compiler', ''))
    exe cd fnameescape(request.directory)
    if a:all
      let &l:efm = '%+G%.%#'
    else
      let &l:efm = request.format
    endif
    let &l:makeprg = request.command
    silent doautocmd QuickFixCmdPre cgetfile
    execute 'cgetfile '.fnameescape(request.file)
    silent doautocmd QuickFixCmdPost cgetfile
  catch '^E40:'
    return v:exception
  finally
    exe cd fnameescape(dir)
    let &l:efm = efm
    let &l:makeprg = makeprg
    call s:set_current_compiler(compiler)
  endtry
  call s:open_quickfix(request, a:copen)
endfunction

function! s:open_quickfix(request, copen) abort
  let was_qf = &buftype ==# 'quickfix'
  execute 'botright' (!empty(getqflist()) || a:copen) ? 'copen' : 'cwindow'
  if &buftype ==# 'quickfix' && !was_qf && !a:copen
    wincmd p
  endif
  for winnr in range(1, winnr('$'))
    if getwinvar(winnr, '&buftype') ==# 'quickfix'
      call setwinvar(winnr, 'quickfix_title', ':' . a:request.expanded)
      let bufnr = winbufnr(winnr)
      call setbufvar(bufnr, '&efm', a:request.format)
      call setbufvar(bufnr, 'dispatch', escape(a:request.expanded, '%#'))
      if has_key(a:request, 'program')
        call setbufvar(bufnr, '&makeprg', a:request.program)
      endif
      if has_key(a:request, 'compiler')
        call setbufvar(bufnr, 'current_compiler', a:request.compiler)
      endif
    endif
  endfor
endfunction

" }}}1
