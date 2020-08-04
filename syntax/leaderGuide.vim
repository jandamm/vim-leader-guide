if exists('b:current_syntax')
	finish
endif
let b:current_syntax = 'leaderguide'

syn region LeaderGuideKeys start="\["hs=e+1 end="\]\s"he=s-1
			\ contained
syn region LeaderGuideBrackets start="\(^\|\s\)\[" end="\]\s"
			\ contains=LeaderGuideKeys keepend
			\ contained

syn region LeaderGuideDesc start="\(^\|\s\)\[[^ ]\+\] [^+]" end="\s\["me=e-2
			\ contains=LeaderGuideBrackets keepend
syn region LeaderGuideMenu start="\(^\|\s\)\[[^ ]\+\] +" end="\s\["me=e-2
			\ contains=LeaderGuideBrackets keepend

hi def link LeaderGuideMenu Title
hi def link LeaderGuideDesc Identifier
hi def link LeaderGuideKeys Type
hi def link LeaderGuideBrackets Delimiter
