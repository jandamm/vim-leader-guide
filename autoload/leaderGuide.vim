let s:save_cpo = &cpoptions
set cpoptions&vim

function! leaderGuide#add_trigger(name, fun) abort " {{{
	if !exists('s:triggers')
		let s:triggers = {}
	endif

	if type(a:fun) ==? type(function('tr'))
		let s:triggers[a:name] = a:fun
	elseif has_key(s:triggers, a:name)
		unlet! s:triggers[a:name]
	endif
endfunction " }}}
function! leaderGuide#has_configuration() abort " {{{
	return exists('s:desc_lookup')
endfunction "}}}
function! leaderGuide#register_prefix_descriptions(key, dictname) abort " {{{
	let key = a:key ==? '<Space>' ? ' ' : a:key
	if !exists('s:desc_lookup')
		call s:create_cache()
	endif
	if strlen(key) == 0
		let s:desc_lookup['top'] = a:dictname
		return
	endif
	if !has_key(s:desc_lookup, key)
		let s:desc_lookup[key] = a:dictname
	endif
endfunction "}}}
function! s:create_cache() abort " {{{
	let s:desc_lookup = {}
	let s:cached_dicts = {}
endfunction " }}}
function! s:create_target_dict(key) abort " {{{
	if has_key(s:desc_lookup, 'top')
		let toplevel = deepcopy({s:desc_lookup['top']})
		let tardict = s:toplevel ? toplevel : get(toplevel, a:key, {})
		let mapdict = s:cached_dicts[a:key]
		call s:merge(tardict, mapdict)
	elseif has_key(s:desc_lookup, a:key)
		let tardict = deepcopy({s:desc_lookup[a:key]})
		let mapdict = s:cached_dicts[a:key]
		call s:merge(tardict, mapdict)
	else
		let tardict = s:cached_dicts[a:key]
	endif
	return tardict
endfunction " }}}
function! s:merge(dict_t, dict_o) abort " {{{
	let target = a:dict_t
	let other = a:dict_o
	for k in keys(target)
		if type(target[k]) == type({}) && has_key(other, k)
			if type(other[k]) == type({})
				if has_key(target[k], 'name')
					let other[k].name = target[k].name
				endif
				call s:merge(target[k], other[k])
			elseif type(other[k]) == type([])
				if g:leaderGuide_flatten == 0 || type(target[k]) == type({})
					let target[k.'m'] = target[k]
				endif
				let target[k] = other[k]
				if has_key(other, k.'m') && type(other[k.'m']) == type({})
					call s:merge(target[k.'m'], other[k.'m'])
				endif
			endif
		elseif type(target[k]) == type('') && has_key(other, k) && k !=? 'name'
			let target[k] = [other[k][0], target[k]]
		elseif type(target[k]) == type('') && !has_key(other, k) && k !=? 'name'
			unlet target[k]
		endif
	endfor
	call extend(target, other, 'keep')
endfunction " }}}

function! leaderGuide#populate_dictionary(key, dictname) abort " {{{
	call s:start_parser(a:key, s:cached_dicts[a:key])
endfunction " }}}
function! leaderGuide#parse_mappings() abort " {{{
	for [k, v] in items(s:cached_dicts)
		call s:start_parser(k, v)
	endfor
endfunction " }}}


function! s:start_parser(key, dict) abort " {{{
	let key = a:key ==? ' ' ? '<Space>' : a:key
	let readmap = ''
	redir => readmap
	silent execute 'map '.key
	redir END
	let lines = split(readmap, "\n")
	let visual = s:vis ==? 'gv' ? 1 : 0

	for line in lines
		let mapd = maparg(split(line[3:])[0], line[0], 0, 1)
		if mapd.lhs =~? '<Plug>.*' || mapd.lhs =~? '<SNR>.*'
			continue
		endif
		let mapd.display = s:format_displaystring(mapd.rhs)
		let mapd.lhs = substitute(mapd.lhs, key, '', '')
		let mapd.lhs = substitute(mapd.lhs, '<Space>', ' ', 'g')
		let mapd.lhs = substitute(mapd.lhs, '<Tab>', '<C-I>', 'g')
		let mapd.rhs = substitute(mapd.rhs, '<SID>', '<SNR>'.mapd['sid'].'_', 'g')
		if mapd.lhs !=# '' && mapd.display !~# 'LeaderGuide.*'
			if (visual && match(mapd.mode, '[vx ]') >= 0) ||
						\ (!visual && match(mapd.mode, '[vx]') == -1)
				let mapd.lhs = s:string_to_keys(mapd.lhs)
				call s:add_map_to_dict(mapd, 0, a:dict)
			endif
		endif
	endfor
endfunction " }}}

function! s:add_map_to_dict(map, level, dict) abort " {{{
	if len(a:map.lhs) > a:level+1
		let curkey = a:map.lhs[a:level]
		let nlevel = a:level+1
		if !has_key(a:dict, curkey)
			let a:dict[curkey] = { 'name' : g:leaderGuide_default_group_name }
			" mapping defined already, flatten this map
		elseif type(a:dict[curkey]) == type([]) && g:leaderGuide_flatten
			let cmd = s:escape_mappings(a:map)
			let curkey = join(a:map.lhs[a:level+0:], '')
			let nlevel = a:level
			if !has_key(a:dict, curkey)
				let a:dict[curkey] = [cmd, a:map.display]
			endif
		elseif type(a:dict[curkey]) == type([]) && g:leaderGuide_flatten == 0
			let cmd = s:escape_mappings(a:map)
			let curkey = curkey.'m'
			if !has_key(a:dict, curkey)
				let a:dict[curkey] = { 'name' : g:leaderGuide_default_group_name }
			endif
		endif
		" next level
		if type(a:dict[curkey]) == type({})
			call s:add_map_to_dict(a:map, nlevel, a:dict[curkey])
		endif
	else
		let cmd = s:escape_mappings(a:map)
		if !has_key(a:dict, a:map.lhs[a:level])
			let a:dict[a:map.lhs[a:level]] = [cmd, a:map.display]
			" spot is taken already, flatten existing submaps
		elseif type(a:dict[a:map.lhs[a:level]]) == type({}) && g:leaderGuide_flatten
			let childmap = s:flattenmap(a:dict[a:map.lhs[a:level]], a:map.lhs[a:level])
			for it in keys(childmap)
				let a:dict[it] = childmap[it]
			endfor
			let a:dict[a:map.lhs[a:level]] = [cmd, a:map.display]
		endif
	endif
endfunction " }}}
function! s:format_displaystring(map) abort " {{{
	let g:leaderGuide#displayname = s:cmd_rename(a:map, 0)[0]
	for Fun in g:leaderGuide_displayfunc
		call Fun()
	endfor
	let display = g:leaderGuide#displayname
	unlet g:leaderGuide#displayname
	return display
endfunction " }}}
function! s:flattenmap(dict, str) abort " {{{
	let ret = {}
	for kv in keys(a:dict)
		if type(a:dict[kv]) == type([])
			let toret = {}
			let toret[a:str.kv] = a:dict[kv]
			return toret
		elseif type(a:dict[kv]) == type({})
			let strcall = a:str.kv
			call extend(ret, s:flattenmap(a:dict[kv], a:str.kv))
		endif
	endfor
	return ret
endfunction " }}}

function! s:cmd_rename(string, escaped) abort
	let escape = a:escaped ? '\\' : ''
	let cmd_reg = '\v^%(:|\V'.escape.'<CMD>\v)(.*)\V'.escape.'<CR>\v$'
	if a:string =~? cmd_reg
		return [substitute(a:string, cmd_reg, '\1', ''), 1]
	else
		return [a:string, 0]
	endif
endfunction
function! s:escape_mappings(mapping) abort " {{{
	let feedkeyargs = a:mapping.noremap ? 'n' : 'm'
	let format = 'silent call feedkeys(%s, "'.feedkeyargs.'")'
	let rstring = substitute(a:mapping.rhs, '\', '\\\\', 'g')
	let rstring = substitute(rstring, '<\([^<>]*\)>', '\\<\1>', 'g')
	let rstring = substitute(rstring, '"', '\\"', 'g')
	if a:mapping.expr
		let rstring = printf(format, 'eval("'.rstring.'")')
	else
		" let [rstring, cmd] = s:cmd_rename(rstring, 1)
		" if cmd
		" 	" Don't escape <SNR> when in command mode
		" 	let rstring = substitute(rstring, '\V\\<SNR>', '<SNR>', '')
		" 	let rstring = substitute(rstring, '^\V\\<C-u>', '', '')
		" else
			let rstring = printf(format, '"'.rstring.'"')
		" endif
	endif
	return rstring
endfunction " }}}
function! s:string_to_keys(input) abort " {{{
	" Avoid special case: <>
	if match(a:input, '<.\+>') != -1
		let retlist = []
		let si = 0
		let go = 1
		while si < len(a:input)
			if go
				call add(retlist, a:input[si])
			else
				let retlist[-1] .= a:input[si]
			endif
			if a:input[si] ==? '<'
				let go = 0
			elseif a:input[si] ==? '>'
				let go = 1
			end
			let si += 1
		endw
		return retlist
	else
		return split(a:input, '\zs')
	endif
endfunction " }}}
function! s:escape_keys(inp) abort " {{{
	let ret = substitute(a:inp, '<', '<lt>', '')
	return substitute(ret, '|', '<Bar>', '')
endfunction " }}}
function! s:show_displayname(inp) abort " {{{
	if has_key(s:displaynames, toupper(a:inp))
		return s:displaynames[toupper(a:inp)]
	else
		let output = a:inp
		for key in keys(s:displaynames)
			let output = substitute(output, '\c\V'.key, '_'.s:displaynames[key], '')
		endfor
		return output
	end
endfunction " }}}
" displaynames {{{1 "
let s:displaynames = {
			\ '<C-I>' : 'TAB',
			\ '<TAB>' : 'TAB',
			\ '<CR>'  : 'CR',
			\ '<BS>'  : 'BS',
			\ '<C-H>' : 'BS',
			\ '<ESC>' : 'ESC',
			\ ' '     : 'SPC',
			\ '<F1>'  : 'F1', '<F2>'   : 'F2', '<F3>'   : 'F3', '<F4>'   : 'F4', '<F5>'   : 'F5',
			\ '<F6>'  : 'F6', '<F7>'   : 'F7', '<F8>'   : 'F8', '<F9>'   : 'F9', '<F10>'  : 'F10',
			\ '<F11>' : 'F11', '<F12>' : 'F12', '<F13>' : 'F13', '<F14>' : 'F14', '<F15>' : 'F15',
			\ '<F16>' : 'F16', '<F17>' : 'F17', '<F18>' : 'F18', '<F19>' : 'F19', '<F20>' : 'F20',
			\ }
" 1}}} "

function! s:calc_layout() abort " {{{
	let ret = {}
	let smap = filter(copy(s:lmap), '(v:key !=# "name") && !(type(v:val) == type([]) && v:val[1] ==# "leader_ignore")')
	let ret.n_items = len(smap)
	let length = values(map(smap,
				\ 'strdisplaywidth("[".v:key."]".'.
				\ '(type(v:val) == type({}) ? "+".v:val["name"] : v:val[1]))'))
	let maxlength = max(length) + g:leaderGuide_hspace
	if g:leaderGuide_vertical
		let ret.n_rows = winheight(0) - 2
		let ret.n_cols = ret.n_items / ret.n_rows + (ret.n_items != ret.n_rows)
		let ret.col_width = maxlength
		let ret.win_dim = ret.n_cols * ret.col_width
	else
		let ret.n_cols = winwidth(0) / maxlength
		if ret.n_cols == 0 | let ret.n_cols = 1 | endif
		let ret.col_width = winwidth(0) / ret.n_cols
		let ret.n_rows = ret.n_items / ret.n_cols + (fmod(ret.n_items,ret.n_cols) > 0 ? 1 : 0)
		let ret.win_dim = ret.n_rows
	endif
	return ret
endfunction " }}}
function! s:create_string(layout) abort " {{{
	let l = a:layout
	let l.capacity = l.n_rows * l.n_cols
	let overcap = l.capacity - l.n_items
	let overh = l.n_cols - overcap
	let n_rows =  l.n_rows - 1

	let bs = 0

	let rows = []
	let row = 0
	let col = 0
	let smap = sort(filter(keys(s:lmap), 'v:val !=# "name"'),'1')
	for k in smap
		if k ==? '<BS>' | let bs = 1 | endif
		silent execute 'cnoremap <nowait> <buffer> '.substitute(k, '|', '<Bar>', ''). ' <C-u>' . s:escape_keys(k) .'<CR>'
		let desc = type(s:lmap[k]) == type({}) ? s:lmap[k].name : s:lmap[k][1]
		if desc ==? 'leader_ignore' | continue | endif
		let displaystring = '['.s:show_displayname(k).'] '.(type(s:lmap[k]) == type({}) ? '+' : '').desc
		let crow = get(rows, row, [])
		if empty(crow)
			call add(rows, crow)
		endif
		call add(crow, displaystring)
		call add(crow, repeat(' ', l.col_width - strdisplaywidth(displaystring)))

		if !g:leaderGuide_sort_horizontal
			if row >= n_rows - 1
				if overh > 0 && row < n_rows
					let overh -= 1
					let row += 1
				else
					let row = 0
					let col += 1
				endif
			else
				let row += 1
			endif
		else
			if col == l.n_cols - 1
				let row +=1
				let col = 0
			else
				let col += 1
			endif
		endif
	endfor
	let r = []
	let mlen = 0
	for ro in rows
		let line = join(ro, '')
		call add(r, line)
		if strdisplaywidth(line) > mlen
			let mlen = strdisplaywidth(line)
		endif
	endfor
	call insert(r, '')
	let output = join(r, "\n ")
	cnoremap <nowait> <buffer> <Space> <C-u><Space><CR>
	if !bs
		let map = s:current_level == 1 ? '\<ESC>' : '<LGCMD>back\<CR>'
		silent execute 'cnoremap <nowait> <expr> <buffer> <BS> empty(getcmdline()) ? "'.map.'" : "\<BS>"'
	endif
	cnoremap <nowait> <buffer> <silent> <c-c> <LGCMD>submode<CR>
	return output
endfunction " }}}


function! s:trigger_before_open() abort " {{{
	let trigger_name = 'before_open'
	if !exists('s:triggers') || !has_key(s:triggers, trigger_name)
		return
	endif

	let g:leaderGuide#context = {
				\ 'type' : 'trigger',
				\ 'name' : trigger_name,
				\ 'display': s:lmap,
				\ 'level': s:current_level,
				\ 'register': s:reg,
				\ 'visual': s:vis ==# '',
				\ 'count': s:count,
				\ 'winv': s:winv,
				\ 'winnr': s:winnr,
				\ 'winres': s:winres
				\ }

	let Fun = s:triggers[trigger_name]
	call Fun()
endfunction " }}}

function! s:start_buffer() abort " {{{
	let s:winv = winsaveview()
	let s:winnr = winnr()
	let s:winres = winrestcmd()

	call s:trigger_before_open()

	call s:winopen()
	let layout = s:calc_layout()
	let string = s:create_string(layout)

	if g:leaderGuide_max_size
		let layout.win_dim = min([g:leaderGuide_max_size, layout.win_dim])
	endif

	setlocal modifiable
	if g:leaderGuide_vertical
		noautocmd execute 'vert res '.layout.win_dim
	else
		noautocmd execute 'res '.layout.win_dim
	endif
	silent 1put!=string
	normal! gg"_dd
	setlocal nomodifiable
	call s:wait_for_input()
endfunction " }}}
function! s:handle_input(input) abort " {{{
	call s:winclose()
	if type(a:input) ==? type({})
		let s:current_level += 1
		let s:lmap = a:input
		call s:start_buffer()
	else
		call feedkeys(s:vis.s:reg.s:count, 'ti')
		if type(a:input) !=? type([])
			let last = strpart(s:last_inp[-1], strchars(s:last_inp[-1]) - 1)
			if s:last_inp[0] !=? last
				execute s:escape_mappings({'rhs': join(s:last_inp, ''), 'noremap': 0})
			endif
			return
		endif
		redraw
		try
			unsilent execute a:input[0]
		catch
			unsilent echom v:exception
		endtry
	endif
endfunction " }}}
function! s:wait_for_input() abort " {{{
	redraw
	let curr_inp = input('')
	if curr_inp ==? ''
		call s:winclose()
	elseif match(curr_inp, '<LGCMD>back') != -1
		call s:winclose()
		let s:current_level -= 1
		call remove(s:last_inp, -1)
		call remove(s:last_name, -1)
		if empty(s:last_inp) | return | endif
		let s:lmap = s:get_cur_map()
		call s:start_buffer()
	elseif match(curr_inp, '^<LGCMD>submode') == 0
		call s:submode_mappings()
	else
		call add(s:last_inp, curr_inp)
		let fsel = get(s:lmap, curr_inp)
		if type(fsel) == type({})
			call add(s:last_name, get(fsel, 'name', ''))
		endif
		call s:handle_input(fsel)
	endif
endfunction " }}}
function! s:get_cur_map() abort
	let lmap = s:mmap
	for key in s:last_inp[1:]
		let lmap = lmap[key]
	endfor
	return lmap
endfunction
function! s:winopen() abort " {{{
	if !exists('s:bufnr')
		let s:bufnr = -1
	endif
	let pos = g:leaderGuide_position ==? 'topleft' ? 'topleft' : 'botright'
	if bufexists(s:bufnr)
		let qfbuf = &buftype ==# 'quickfix'
		let splitcmd = g:leaderGuide_vertical ? ' 1vs' : ' 1sp'
		noautocmd execute pos.splitcmd
		let bnum = bufnr('%')
		noautocmd execute 'buffer '.s:bufnr
		cmapclear <buffer>
		if qfbuf
			noautocmd execute bnum.'bwipeout!'
		endif
	else
		let splitcmd = g:leaderGuide_vertical ? ' 1vnew' : ' 1new'
		noautocmd execute pos.splitcmd
		let s:bufnr = bufnr('%')
		augroup leaderguide_winopen_autoclose_group
			autocmd!
			autocmd WinLeave <buffer> call s:winclose()
		augroup END
	endif
	let s:gwin = winnr()
	setlocal filetype=leaderGuide
	setlocal nonumber norelativenumber nolist nomodeline nowrap nopaste
	setlocal nobuflisted buftype=nofile bufhidden=unload noswapfile
	setlocal nocursorline nocursorcolumn colorcolumn=
	setlocal winfixwidth winfixheight
	call setwinvar(winnr(), '&statusline', '%!s:statusline()')
endfunction " }}}
function! s:statusline() abort
	let ret = join(map(filter(copy(s:last_inp), 'v:val !=? "<buffer>"'), { _, key -> s:show_displayname(key) }))
	if !empty(ret)
		let ret = '%#LeaderGuideKeysStatusline#'.ret.'%*%='
	endif
	let name = s:last_name[-1]
	if !empty(name)
		let group_prefix = empty(ret) ? '' : '+'
		let ret .= '%#LeaderGuideMenuStatusline#'.group_prefix.name.'%*'
	elseif empty(ret)
		let ret = 'Leader Guide'
	endif
	return ret
endfunction
function! s:winclose() abort " {{{
	noautocmd execute s:gwin.'wincmd w'
	if s:gwin == winnr()
		close
		exe s:winres
		let s:gwin = -1
		noautocmd execute s:winnr.'wincmd w'
		call winrestview(s:winv)
	endif
endfunction " }}}
function! s:page_down() abort " {{{
	call feedkeys("\<c-c>", 'n')
	call feedkeys("\<c-f>", 'x')
	call s:wait_for_input()
endfunction " }}}
function! s:page_up() abort " {{{
	call feedkeys("\<c-c>", 'n')
	call feedkeys("\<c-b>", 'x')
	call s:wait_for_input()
endfunction " }}}

function! s:handle_submode_mapping(cmd) abort " {{{
	if a:cmd ==? '<LGCMD>page_down'
		call s:page_down()
	elseif a:cmd ==? '<LGCMD>page_up'
		call s:page_up()
	elseif a:cmd ==? '<LGCMD>win_close'
		call s:winclose()
	endif
endfunction " }}}
function! s:submode_mappings() abort " {{{
	let submodestring = ''
	let maplist = []
	for key in items(g:leaderGuide_submode_mappings)
		let map = maparg(key[0], 'c', 0, 1)
		if !empty(map)
			call add(maplist, map)
		endif
		execute 'cnoremap <nowait> <silent> <buffer> '.key[0].' <LGCMD>'.key[1].'<CR>'
		let submodestring = submodestring.' '.key[0].': '.key[1].','
	endfor
	let inp = input(strpart(submodestring, 0, strlen(submodestring)-1))
	for map in maplist
		call s:mapmaparg(map)
	endfor
	silent call s:handle_submode_mapping(inp)
endfunction " }}}
function! s:mapmaparg(maparg) abort " {{{
	let noremap = a:maparg.noremap ? 'noremap' : 'map'
	let buffer = a:maparg.buffer ? '<buffer> ' : ''
	let silent = a:maparg.silent ? '<silent> ' : ''
	let nowait = a:maparg.nowait ? '<nowait> ' : ''
	let st = a:maparg.mode.''.noremap.' '.nowait.silent.buffer.''.a:maparg.lhs.' '.a:maparg.rhs
	execute st
endfunction " }}}

function! s:get_register() abort " {{{
	if match(&clipboard, 'unnamedplus') >= 0
		let clip = '+'
	elseif match(&clipboard, 'unnamed') >= 0
		let clip = '*'
	else
		let clip = '"'
	endif
	return clip
endfunction "}}}
function! s:init_on_call(vis) abort " {{{
	let s:vis = a:vis ? 'gv' : ''
	let s:count = v:count != 0 ? v:count : ''
	let s:current_level = 1
	let s:last_inp = []
	let s:last_name = []

	if has('nvim') && !exists('s:reg')
		let s:reg = ''
	else
		let s:reg = v:register != s:get_register() ? '"'.v:register : ''
	endif
endfunction " }}}
function! leaderGuide#start_by_prefix(vis, key) abort " {{{

	call s:init_on_call(a:vis)
	call add(s:last_inp, a:key)

	let s:toplevel = a:key ==? '  '
	if !has_key(s:cached_dicts, a:key) || g:leaderGuide_run_map_on_popup
		"first run
		let s:cached_dicts[a:key] = {}
		call s:start_parser(a:key, s:cached_dicts[a:key])
	endif

	if has_key(s:desc_lookup, a:key) || has_key(s:desc_lookup , 'top')
		let rundict = s:create_target_dict(a:key)
	else
		let rundict = s:cached_dicts[a:key]
	endif

	call s:start_with_dict(rundict)
endfunction " }}}
function! leaderGuide#start(vis, dict) abort " {{{
	call s:init_on_call(a:vis)
	call s:start_with_dict(a:dict)
endfunction " }}}
function! s:start_with_dict(dict) abort
	let s:lmap = a:dict
	let s:mmap = a:dict

	call add(s:last_name, get(a:dict, 'name', ''))

	call s:start_buffer()
endfunction

let &cpoptions = s:save_cpo
unlet s:save_cpo
