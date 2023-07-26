#!/bin/bash

years="2016 2017 2018 2019 2020 2021 2022 2023"
repos="sonic-net/sonic-buildimage"
months="01 02 03 04 05 06 07 08 09 10 11 12"
keys="additions,author,baseRefName,number,title,mergedAt"
interval=20
debug="#"
dump_type="prs"
bypass_year="n"

help(){
    echo "Use:"
    echo "    -i     # gh request interval, default $interval"
    echo "    -x     # if run gh command, default dry run"
    echo "    -y     # specify year list, default $years"
    echo "    -r     # repo list, default $repos"
    echo "    -t     # dump type[prs,reviews], default prs"
    echo "    -m     # dump by month, default by year"
}

while [[ $# > 0 ]]
do
    case "$1" in
        -r)
            repos=$2
            shift
            ;;
        -x)
            debug=""
            ;;
        -y)
            years=$2
            shift
            ;;
        -i)
            interval=$2
            shift
            ;;
        -t)
            dump_type=$2
            shift
            ;;
        -m)
            bypass_year="y"
            ;;
        -k)
            add_keys=$2
            shift
            ;;
        *)
            help
            exit 1
            ;;
    esac
    shift
done

[[ "$dump_type" == "reviews" ]] && keys="number,comments,latestReviews,reviews"
[[ "$dump_type" == "prs" ]] && keys+=$add_keys

echo years:    $years
echo repos:    $repos
echo months:    $months
echo keys:    $keys
echo interval:    $interval
echo debug:    $debug
echo dump:    $dump_type

check_dump_file(){
    file=$1
    [ -f $file ] || return 11
    length=$(cat $file | jq length)
    [[ $? != 0 ]] && return 12
    echo $file,$length
    echo $length | grep -e '00$' -e '^1$' && echo Warning: $file,$length !!!!!!!!!! 1>&2 && return 13
    return 0
}

for year in $years
do
    echo year: $year
    mkdir -p $year
    for org_repo in $repos
    do
        repo=$(echo $org_repo | awk -F/ '{print$2}')
        org=$(echo $org_repo | awk -F/ '{print$1}')
        echo "    " repo: $repo
        # try dump by year when bypass_year==n and no monthly dump files
        file_by_year=$year/$repo.$dump_type.json
        if [[ "$bypass_year" == n ]] && [ -z "$(ls $year/$repo.*.$dump_type.json 2>/dev/null)" ];then
            check_dump_file $file_by_year && continue
            rm -rf $file_by_year
            eval $debug gh pr list -R $org_repo -L 10000 -s merged --json $keys -S "merged:$year-01-01..$year-12-31" | jq --indent 4 ".[] += {repo: \"$repo\", author: .[].author.login} | sort_by(.number)"  > $file_by_year
            sleep $interval
            check_dump_file $file_by_year && continue
        fi

        # try dump by month, when dump by year failed
        for month in $months
        do
            file_by_month=$year/$repo.$month.$dump_type.json
            start=$year-$month-01
            # if the last day is not correct, download will fail.
            end=$(date -d "$year/$month/1 + 1 month -1 day" "+%Y-%m-%d")
            echo "        $start,$end"
            check_dump_file $file_by_month && continue
            eval $debug gh pr list -R $org_repo -L 10000 -s merged --json $keys -S "merged:$start..$end" | jq --indent 4 ".[] += {repo: \"$repo\"}" > $file_by_month
            sleep $interval
            check_dump_file $file_by_month && continue

            # try dump by 10 days, when dump by month failed
            eval $debug gh pr list -R $org_repo -L 10000 -s merged --json $keys -S "merged:$year-$month-01..$year-$month-10" | jq --indent 4 ".[] += {repo: \"$repo\"}" > $year/$repo.$month.a.$dump_type.json
            check_dump_file $year/$repo.$month.a.$dump_type.json || { echo "gh pr list -R $org_repo -L 10000 -s merged --json $keys -S \"merged:$year-$month-01..$year-$month-10\""; exit 111; }
            sleep 10
            eval $debug gh pr list -R $org_repo -L 10000 -s merged --json $keys -S "merged:$year-$month-11..$year-$month-20" | jq --indent 4 ".[] += {repo: \"$repo\"}" > $year/$repo.$month.b.$dump_type.json
            check_dump_file $year/$repo.$month.b.$dump_type.json || { echo "gh pr list -R $org_repo -L 10000 -s merged --json $keys -S\"merged:$year-$month-11..$year-$month-20\""; exit 112; }
            sleep 10
            eval $debug gh pr list -R $org_repo -L 10000 -s merged --json $keys -S "merged:$year-$month-21..$end" | jq --indent 4 ".[] += {repo: \"$repo\"}" > $year/$repo.$month.c.$dump_type.json
            check_dump_file $year/$repo.$month.c.$dump_type.json || { echo "gh pr list -R $org_repo -L 10000 -s merged --json $keys -S\"merged:$year-$month-21..$end\""; exit 113; }
            sleep $interval
            jq 'add | sort_by(.number)' --indent 4 $year/$repo.$month.a.$dump_type.json $year/$repo.$month.b.$dump_type.json $year/$repo.$month.c.$dump_type.json > $year/$repo.$month.$dump_type.json
        done    
        jq 'add | sort_by(.number)' --indent 4 $year/$repo.*.$dump_type.json > $file_by_year
        git add $file_by_year
    done
done
