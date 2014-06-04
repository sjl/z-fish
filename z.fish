# maintains a jump-list of the directories you actually use
#
# INSTALL:
#   * put something like this in your config.fish:
#     . /path/to/z.fish
#   * put something like this in your fish_prompt function:
#       z --add "$PWD"
#   * cd around for a while to build up the db
#   * PROFIT!!
#
# USE:
#   * z foo     # goes to most frecent dir matching foo
#   * z foo bar # goes to most frecent dir matching foo and bar
#   * z -r foo  # goes to highest ranked dir matching foo
#   * z -t foo  # goes to most recently accessed dir matching foo
#   * z -l foo  # list all dirs matching foo (by frecency)

function z -d "Jump to a recent directory."
    set -l __Z_DATA "$HOME/.z"

    # add entries
    if [ "$argv[1]" = "--add" ]
        set -e argv[1]

        # $HOME isn't worth matching
        [ "$argv" = "$HOME" ]; and return

		set -l tempfile (mktemp $__Z_DATA.XXXXXX)
		test -f $tempfile; or return
		
        # maintain the file
        awk -v path="$argv" -v now=(date +%s) -F"|" '
            BEGIN {
                rank[path] = 1
                time[path] = now
            }
            $2 >= 1 {
                # drop ranks below 1
                if( $1 == path ) {
                    rank[$1] = $2 + 1
                    time[$1] = now
                } else {
                    rank[$1] = $2
                    time[$1] = $3
                }
                count += $2
            }
            END {
                if( count > 6000 ) {
                    # aging
                    for( x in rank ) print x "|" 0.99*rank[x] "|" time[x]
                } else for( x in rank ) print x "|" rank[x] "|" time[x]
            }
        ' $__Z_DATA ^/dev/null > $tempfile
        mv -f $tempfile $__Z_DATA

    # tab completion
    else
        if [ "$argv[1]" = "--complete" ]
            awk -v q="$argv[2]" -F"|" '
                  BEGIN {
                if( q == tolower(q) ) imatch = 1
                split(substr(q, 3), fnd, " ")
            }
            {
                if( imatch ) {
                    for( x in fnd ) tolower($1) !~ tolower(fnd[x]) && $1 = ""
                } else {
                    for( x in fnd ) $1 !~ fnd[x] && $1 = ""
                }
                if( $1 ) print $1
            }
            ' "$__Z_DATA" 2>/dev/null

        else
            # list/go
            set -l last ''
            set -l list 0
            set -l typ ''
            set -l fnd ''
            
            while [ (count $argv) -gt 0 ]
                switch "$argv[1]"
                    case -- '-h'
                        echo "z [-h][-l][-r][-t] args" >&2
                        return
                    case -- '-l'
                        set list 1
                    case -- '-r'
                        set typ "rank"
                    case -- '-t'
                        set typ "recent"
                    case -- '--'
                        while [ "$argv[1]" ]
                            set -e argv[1]
                            set fnd "$fnd $argv[1]"
                        end
                    case '*'
                        set fnd "$fnd $argv[1]"
                end
                set last $1
                set -e argv[1]
            end

            [ "$fnd" ]; or set list 1

            # if we hit enter on a completion just go there
            [ -d "$last" ]; and cd "$last"; and return

            # no file yet
            [ -f "$__Z_DATA" ]; or return

			set -l tempfile (mktemp $__Z_DATA.XXXXXX)
			test -f $tempfile; or return

            set -l target (awk -v t=(date +%s) -v list="$list" -v typ="$typ" -v q="$fnd" -v tmpfl="$tempfile" -F"|" '
                function frecent(rank, time) {
                # relate frequency and time
                dx = t - time
                if( dx < 3600 ) return rank * 4
                if( dx < 86400 ) return rank * 2
                if( dx < 604800 ) return rank / 2
                return rank / 4
            }
            function output(files, out, common) {
                # list or return the desired directory
                if( list ) {
                    cmd = "sort -n >&2"
                    for( x in files ) {
                        if( files[x] ) printf "%-10s %s\n", files[x], x | cmd
                    }
                    if( common ) {
                        printf "%-10s %s\n", "common:", common > "/dev/stderr"
                    }
                } else {
                    if( common ) out = common
                    print out
                }
            }
            function common(matches) {
                # find the common root of a list of matches, if it exists
                for( x in matches ) {
                    if( matches[x] && (!short || length(x) < length(short)) ) {
                        short = x
                    }
                }
                if( short == "/" ) return
                # use a copy to escape special characters, as we want to return
                # the original. yeah, this escaping is awful.
                clean_short = short
                gsub(/[\(\)\[\]\|]/, "\\\\&", clean_short)
                for( x in matches ) if( matches[x] && x !~ clean_short ) return
                return short
            }
            BEGIN { split(q, words, " "); hi_rank = ihi_rank = -9999999999 }
            {
                if( typ == "rank" ) {
                    rank = $2
                } else if( typ == "recent" ) {
                    rank = $3 - t
                } else rank = frecent($2, $3)
                matches[$1] = imatches[$1] = rank
                for( x in words ) {
                    if( $1 !~ words[x] ) delete matches[$1]
                    if( tolower($1) !~ tolower(words[x]) ) delete imatches[$1]
                }
                if( matches[$1] && matches[$1] > hi_rank ) {
                    best_match = $1
                    hi_rank = matches[$1]
                } else if( imatches[$1] && imatches[$1] > ihi_rank ) {
                    ibest_match = $1
                    ihi_rank = imatches[$1]
                }
            }
            END {
                # prefer case sensitive
                if( best_match ) {
                    output(matches, best_match, common(matches))
                } else if( ibest_match ) {
                    output(imatches, ibest_match, common(imatches))
                }
            }
            ' $__Z_DATA)
            

            rm -f $tempfile
            if [ $status -gt 0 ]
            
            else
                [ "$target" ]; and cd "$target"
            end
        end
    end
end	

function __z_init -d 'Set up automatic population of the directory list for z'
	functions fish_prompt | grep -q 'z --add'
	if [ $status -gt 0 ]
		functions fish_prompt | sed -e '$ i\\
		z --add "$PWD"' | .
	end
end

__z_init
