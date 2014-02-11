#!/usr/bin/env bash

trap "clean_up && exit 1" TERM
trap "clean_up && exit 1" INT

export __me=$$

RED="\033[1;31m"
GREEN="\033[1;32m"
YELLOW="\033[1;33m"
CYAN="\033[1;36m"
RESET="\033[0m"

function clean_up
{
    rm *.htm* >/dev/null 2>&1
    rm .*.htm* >/dev/null 2>&1
    rm .${out_file} >/dev/null 2>&1
    rm .tmp >/dev/null 2>&1

    return 0
}

function die
{
    type -p clean_up

    if [ $? -eq 0 ]; then
        clean_up
    fi

    echo -e "${RED}error:${RESET} $1"
    kill -s TERM $__me

    return 1
}

function warn
{

    echo -e "${YELLOW}warning: $1${RESET}"
    return 0
}

function logger
{
    unset arr
    arr=()
    for((i=1;i<=$#;i++))
    do
        arr+=( "${!i}" )
    done

    stamp=`date +"%Y %b %d %H:%M:%S"`

    # echo $stamp

    echo -e "$stamp:" >>$log_source
    "${arr[0]}" "${arr[@]:1}" >>$log_source 2>>$log_source

    return $?
}

function get
{
    echo -ne "fetching ${YELLOW}$1${RESET}... "
    logger wget "$1"
    op=$?

    if [ $op -ne 0 ]; then
        logger ${get_prefix_1} wget "$1"
        op=$?
    fi

    if [ $op -ne 0 ]; then
        logger ${get_prefix_2} wget "$1"
        op=$?
    fi

    if [ $op -eq 0 ]; then
        echo -e "${GREEN}done${RESET}"
    else
        echo -e "${RED}failed${RESET}"
    fi

    return $op
}

function single_page_render
{
    echo -e "${YELLOW}single-page document${RESET}"
    ${xml} ed -N x="http://www.w3.org/1999/xhtml" \
        -d "//x:h1" -d "//x:h2" -d "//x:h3" -d "//x:h5" \
        -d "//x:p[@class='toplink']" \
        -d "//x:p[@class='updat']" \
        -d "//x:hr[@class='infotop']" \
        -d "//x:p[@class='info']" \
        -d "//x:hr" \
        -d "//x:p[@class='information']" \
        -d "//x:hr[@class='infobot']" \
        -d "//x:p[@class='link']" \
        -d "//x:table[@class='t2h-foot']" \
        "${fname}.${fext}" >.tmp 2>${log_source} \
        || die "invalid single page document format"
    ${xml} sel ---html N x="http://www.w3.org/1999/xhtml" -t -m "x:h4" -c . \
        -n1 ${fname}.${ext} >${log_source} 2>&1
    if [ $? -eq 0 ]; then
        ${xml} ed --html -N x="http://www.w3.org/1999/xhtml" \
            -r "//x:h4" -v "h1" \
            .tmp > $out_file 2>${log_source} \
            || die "unable to replace h4 heading tags with h1"
    else
        cp .tmp $out_file >${log_source} 2>&1
        declare -g webpage_mode="--webpage"
    fi

    return 0
}

function multi_page_render
{
    echo -e "${YELLOW}multi page document${RESET}"
    body_line=$(cat ${fname}.${fext} | tr -d '\n' | grep -o "<body [^>]*>") \
        || "unable to get body tag from multi-page document"
    ${xml} sel --html -N x="http://www.w3.org/1999/xhtml" \
        -t -m "//x:head" -c . \
        -n1 ${fname}.${fext} >${out_file} 2>${log_source} \
        || die "unable to get head tag from multi-page document"
    echo "$body_line" >> ${out_file}

    count_ref=0
    map=0;

    for i in ${c_files[@]}; do
        rm $i >${log_source} 2>&1
        get "${link_rel}/$i" \
            || die "unable to fetch ${CYAN}$i${RESET}"
        echo -ne "processing ${YELLOW}$i${RESET}... "
        ${tidy} -config tidy.config -m $i >${log_source} 2>&1 \
            || warn "${CYAN}applying tidy changes to ${YELLOW}$i${RESET}"
        ${xml} ed -N x="http://www.w3.org/1999/xhtml" \
            -d "//x:h1" -d "//x:h2" -d "//x:h3" -d "//x:h5" \
            -d "//x:p[@class='toplink']" \
            -d "//x:p[@class='updat']" \
            -d "//x:hr[@class='infotop']" \
            -d "//x:p[@class='info']" \
            -d "//x:hr[@class='infobot']" \
            -d "//x:hr" \
            -d "//x:p[@class='information']" \
            -d "//x:p[@class='link']" \
            -d "//x:table[@class='t2h-foot']" \
            $i >.tmp 2>${log_source} \
            || die "unable to remove additional tags from multi-page document"
        ${xml} ed -N x="http://www.w3.org/1999/xhtml" -r "//x:h4" -v "strong" \
            .tmp >.$i 2>${log_source} \
            || die "invalid multi-page document"

        for j in \
            `cat $i | tr -d '\n' | grep -o "<a href=\"#s[0-9]*\">[^>]*>" | sed 's/\(<a href=\"#s\)\([0-9].*\)\(\">[^>]*>\)/\2/g'`; \
            do
            let m=$j+$count_ref;
            sed -i s/href=\"#s$j\"/href=\"#s$m\"/g .$i;
            sed -i s/id=\"s$j\"/id=\"s$m\"/g .$i;
            sed -i s/name=\"s$j\"/name=\"s$m\"/g .$i;
        done;
        count=`cat $i | tr -d '\n' | grep -o "<a href=\"#s[0-9]*\">[^>]*>" | wc -l`
        let count_ref=${count_ref}+${count}
        echo "<h1>${c_titles[$map]}</h1>" >> ${out_file}
        cat .$i | tr -d '\n' | \
            grep -o "<body.*</body>" | \
            sed -e 's/<body[^>]*>//g'| \
            sed -e 's/<\/body>//g' >> ${out_file}
        let map=$map+1
        echo -e "${GREEN}done${RESET}"
    done
    echo "</body>" >> ${out_file}

    return 0
}

if [ $# -lt 1 ]; then
    die "usage: ./convert.sh http://marxists.org/PATH_TO_YOUR_ARTICLE.html"
fi

xml=`which xml` || xml=`which xmlstarlet` || die "unable to find xmlstarlet"
htmldoc=`which htmldoc` || die "unable to find htmldoc"
tidy=`which tidy` || die "unable to find tidy"

get_prefix_1="proxychains -q"
get_prefix_2="tsocks"
log_source="prolpdf.log"
out_file=".compiled.html"

c_files=()
c_titles=()

echo -ne "" > ${log_source}

link_rel=$(echo $1 | sed -e 's/\/[^\/]*.html*\/*//g') \
    || die "unable to generate root link address"
fext=$(echo $1 | grep -o "html*") \
    || die "unable to get file extension"
fname=$(echo $1 | grep -o '/[^\/]*\.html*' | \
    tr -d '/' | sed -e s/\.${fext}//g) \
    || die "unable to get file name"

echo -e "document base address: ${YELLOW}${link_rel}${RESET}"
echo -e "file name (without extension): ${YELLOW}${fname}${RESET}"
echo -e "file extension: ${YELLOW}${fext}${RESET}"

rm ${fname}.{$fext} >${log_source} 2>&1
get "$1" || die "unable to fetch index file"
${tidy} -config tidy.config -m ${fname}.${fext} >${log_source} 2>&1 \
    || warn "${CYAN}applying tidy changes to index file${RESET}"

out_name=$(${xml} sel --html -N x="http://www.w3.org/1999/xhtml" \
    -t -m "//x:head/x:title/text()" -c . \
    -n1 ${fname}.${fext} 2>/dev/null| sed -e 's/[\ -]/_/g' \
    | sed -e 's/[\:\?()]*//g') \
    || die "unable to generate output file name"
echo -e "output file name: ${YELLOW}${out_name}${RESET}"
${xml} sel --html -N x="http://www.w3.org/1999/xhtml" -t -m "//x:big" -c . \
    -n1 ${fname}.${fext} >${log_source} 2>&1

if [ $? -ne 0 ]; then
    single_page_render
else
    ${xml} sel --html -N x="http://www.w3.org/1999/xhtml" \
        -t -m "//x:big/x:a/text()" -c . \
        -n1 ${fname}.${fext} 2>${log_source} | ${xml} esc > .tmp \
        || die "unable to get titles from index file"
    while read line; do
        c_titles+=( "$line" )
    done < .tmp

    ${xml} sel --html -N x="http://www.w3.org/1999/xhtml" \
        -t -m "//x:big/x:a" -v "@href" \
        -n1 ${fname}.${fext} 2>${log_source} > .tmp \
        || die "unable to get chapter files from index index file"
    while read line; do
        c_files+=( "$line" )
    done < .tmp

    if [ "${c_files[0]:0:1}" == "#" ]; then
        single_page_render
    else
        multi_page_render
    fi
fi

echo -e "webpage mode: ${YELLOW}$webpage_mode${RESET}"
echo -ne "generating output pdf document... "
err=$( { ${htmldoc} ${webpage_mode} "${out_file}" -f "${out_name}.pdf"; } 2>&1 )

if [ $? -eq 0 ]; then
    echo -e "${GREEN}done${RESET}"
    echo $err
    clean_up
    exit 0
else
    echo -e "${RED}failed${RESET}"
    echo $err
    clean_up
    exit 1
fi
