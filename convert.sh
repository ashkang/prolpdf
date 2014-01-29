#!/bin/bash

trap "exit 1" TERM
export __me=$$

function clean_up
{
#    rm *.htm
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

function get
{
    proxychains -q wget "$1" >/dev/null 2>&1
    return 0
}

pc_args="-q"
toc_file=".toc.html"

c_files=()
c_titles=()
link_rel=`echo $1 | sed -e 's/index.htm//g'`
rm index.htm >/dev/null 2>&1
get "$1"
tidy -config tidy.config -m index.htm >/dev/null 2>&1

meta=`cat index.htm | tr -d '\n' | grep -o "<meta[^>]*>"`
title=`cat index.htm | grep -o "<title>.*</title>"`
link=`cat index.htm | tr -d '\n' | grep -o "<link rel[^>]*>"`
body_line=`cat index.htm | tr -d '\n' | grep -o "<body [^>]*>"`

echo "<head>" > $toc_file
echo "$meta" >> $toc_file
echo "$title" >> $toc_file
echo "$link" >> $toc_file
echo "</head>" >> $toc_file
echo "$body_line" >> $toc_file

xml sel --html -N x="http://www.w3.org/1999/xhtml" -t -m "//x:big/x:a/text()" -c . -n1 index.htm | xml esc > .tmp
while read line; do
    c_titles+=( "$line" )
done < .tmp

xml sel --html -N x="http://www.w3.org/1999/xhtml" -t -m "//x:big/x:a" -v "@href" -n1 index.htm > .tmp
while read line; do
    c_files+=( "$line" )
done < .tmp

count_ref=0
map=0;

for i in ${c_files[@]}; do
    rm $i >/dev/null 2>/dev/null
    get "${link_rel}/$i"
    echo "processing $i with cr = $count_ref, c = $count"
    tidy -config tidy.config -m $i >/dev/null 2>&1
    xml ed -N x="http://www.w3.org/1999/xhtml" \
        -d "//x:h1" -d "//x:h2" -d "//x:h3" -d "//x:h5" \
        -d "//x:p[@class='toplink']" -d "//x:p[@class='updat']" \
        -d "//x:p[@class='link']" \
        $i > .tmp 2>&1
    xml ed -N x="http://www.w3.org/1999/xhtml" -r "//x:h4" -v "strong" .tmp > .$i 2>&1

    for j in `cat $i | tr -d '\n' | grep -o "<a href=\"#s[0-9]*\">[^>]*>" | sed 's/\(<a href=\"#s\)\([0-9].*\)\(\">[^>]*>\)/\2/g'`; do
        let m=$j+$count_ref;
        sed -i s/href=\"#s$j\"/href=\"#s$m\"/g .$i;
        sed -i s/id=\"s$j\"/id=\"s$m\"/g .$i;
        sed -i s/name=\"s$j\"/name=\"s$m\"/g .$i;
    done;
    count=`cat $i | tr -d '\n' | grep -o "<a href=\"#s[0-9]*\">[^>]*>" | wc -l`
    let count_ref=${count_ref}+${count}
    echo "<h1>${c_titles[$map]}</h1>" >> $toc_file
    # xml sel --html -N x="http://www.w3.org/1999/xhtml" -t -m "//x:body/*" -c . .$i | xml esc >> $toc_file
    cat .$i | tr -d '\n' | grep -o "<body.*</body>" | sed -e 's/<body[^>]*>//g' | sed -e 's/<\/body>//g' >> $toc_file
    let map=$map+1
done
echo "</body>" >> $toc_file
htmldoc $toc_file -f "output.pdf"
# cat $toc_file
# clean_up
