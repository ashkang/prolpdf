#!/bin/bash

trap "exit 1" TERM
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
    rm .out_file >/dev/null 2>&1
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

    return 0
}

function warn
{

    echo -e "${YELLOW}warning: $1${RESET}"
    return 0
}

function get
{
    ${get_prefix} wget "$1" >/dev/null 2>&1
    return $?
}

function single_page_render
{
    echo -e "${YELLOW}single page document${RESET}"
    ${xml} ed -N x="http://www.w3.org/1999/xhtml" \
        -d "//x:h1" -d "//x:h2" -d "//x:h3" -d "//x:h5" \
        -d "//x:p[@class='toplink']" -d "//x:p[@class='updat']" \
        -d "//x:hr[@class='infotop']" -d "//x:p[@class='info']" -d "//x:hr[@class='infobot']" \
        -d "//x:p[@class='link']" \
        "${fname}.${fext}" >.tmp 2>/dev/null \
        || die "invalid single page document format"
    ${xml} ed -N x="http://www.w3.org/1999/xhtml" -r "//x:h4" -v "h1" \
        .tmp > $out_file 2>/dev/null \
        || die "invalis single page document format"

    return 0
}

function multi_page_render
{
    echo -e "${YELLOW}multi page document${RESET}"
    body_line=$(cat ${fname}.${fext} | tr -d '\n' | grep -o "<body [^>]*>") \
        || "unable to get body tag from multi-page document"
    ${xml} sel --html -N x="http://www.w3.org/1999/xhtml" -t -m "//x:head" -c . \
        -n1 ${fname}.${fext} >${out_file} 2>/dev/null \
        || die "unable to get head tag from multi-page document"
    echo "$body_line" >> ${out_file}

    count_ref=0
    map=0;

    for i in ${c_files[@]}; do
        rm $i >/dev/null 2>/dev/null
        get "${link_rel}/$i" \
            || die "unable to fetch ${CYAN}$i${RESET}"
        echo -ne "processing ${YELLOW}$i${RESET}... "
        ${tidy} -config tidy.config -m $i >/dev/null 2>&1 \
            || die "applying tidy changes to ${CYAN}$i${RESET}"
        ${xml} ed -N x="http://www.w3.org/1999/xhtml" \
            -d "//x:h1" -d "//x:h2" -d "//x:h3" -d "//x:h5" \
            -d "//x:p[@class='toplink']" -d "//x:p[@class='updat']" \
            -d "//x:hr[@class='infotop']" -d "//x:p[@class='info']" -d "//x:hr[@class='infobot']" \
            -d "//x:p[@class='link']" \
            $i >.tmp 2>/dev/null \
            || die "unable to remove additional tags from multi-page document"
        ${xml} ed -N x="http://www.w3.org/1999/xhtml" -r "//x:h4" -v "strong" \
            .tmp >.$i 2>/dev/null \
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

xml=`which xml` || die "unable to find xmlstarlet"
htmldoc=`which htmldoc` || die "unable to find htmldoc"
tidy=`which tidy` || die "unable to find tidy"

get_prefix="proxychains -q"
out_file=".toc.html"

c_files=()
c_titles=()

link_rel=$(echo $1 | sed -e 's/\/[^\/]*.html*\/*//g') \
    || die "unable to generate root link address"
fext=$(echo $1 | grep -o "html*") \
    || die "unable to get file extension"
fname=$(echo $1 | grep -o '/[^\/]*\.html*' | tr -d '/' | sed -e s/\.${fext}//g) \
    || die "unable to get file name"

echo -e "link_rel: ${YELLOW}${link_rel}${RESET}"
echo -e "fname: ${YELLOW}${fname}${RESET}"
echo -e "fext: ${YELLOW}${fext}${RESET}"

rm ${fname}.{$fext} >/dev/null 2>&1
get "$1" || die "unable to fetch index file"
${tidy} -config tidy.config -m ${fname}.${fext} >/dev/null 2>&1 \
    || warn "applying tidy changes to index file"

out_name=$(${xml} sel --html -N x="http://www.w3.org/1999/xhtml" -t -m "//x:head/x:title/text()" -c . \
    -n1 ${fname}.${fext} 2>/dev/null| sed -e 's/[\ -]/_/g' | sed -e 's/[\:\?()]*//g') \
    || die "unable to generate output file name"
echo -e "out_name: ${YELLOW}${out_name}${RESET}"
${xml} sel --html -N x="http://www.w3.org/1999/xhtml" -t -m "//x:big" -c . \
    -n1 ${fname}.${fext} >/dev/null 2>&1

if [ $? -ne 0 ]; then
    single_page_render
else
    ${xml} sel --html -N x="http://www.w3.org/1999/xhtml" -t -m "//x:big/x:a/text()" -c . \
        -n1 ${fname}.${fext} 2>/dev/null | ${xml} esc > .tmp \
        || die "unable to get titles from index file"
    while read line; do
        c_titles+=( "$line" )
    done < .tmp

    ${xml} sel --html -N x="http://www.w3.org/1999/xhtml" -t -m "//x:big/x:a" -v "@href" \
        -n1 ${fname}.${fext} 2>/dev/null > .tmp \
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

${htmldoc} "${out_file}" -f "${out_name}.pdf" \
    || die "unable to generate output pdf document"
clean_up
