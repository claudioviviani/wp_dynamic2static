#!/bin/bash
#

cat << EOF
  ___ ___           _______                                           
 |   Y   .-----.   |   _   .----.-----.--------.                      
 |.  |   |  _  |   |.  1___|   _|  _  |        |                      
 |. / \  |   __|   |.  __) |__| |_____|__|__|__|                      
 |:      |__|      |:  |                                              
 |::.|:. |         |::.|                                              
 \`--- ---' ______  \`---'                       __          _______    
          |   _  \ .--.--.-----.---.-.--------|__.----.   |       |   
          |.  |   \|  |  |     |  _  |        |  |  __|   |___|   |   
          |.  |    |___  |__|__|___._|__|__|__|__|____|    /  ___/    
          |:  1    |_____|                                |:  1  \    
          |::.. . /                                       |::.. . |   
          \`------'                                        \`-------'   
                                   _______ __         __   __         
                                  |   _   |  |_.---.-|  |_|__.----.   
                                  |   1___|   _|  _  |   _|  |  __|   
                                  |____   |____|___._|____|__|____|   
                                  |:  1   |                           
                                  |::.. . |                           
                                  \`-------'         by
                                              Claudio Viviani
                                           https://www.homelab.it
                                            info [at] homelab.it

EOF

# Variabile url
url=$1

# Variabile directory destinazione
dirdst=$2

# Variabile attiva/disattiva download YOAST Plugin
# Attivare solo in presenza del plugin YOAST
# 1 = Attivo
# 0 = Non Attivo
yoast="1"

# Estrapolo dominio dall'url
domain=$(echo $url | sed -e 's|^[^/]*//||' -e 's|/.*$||')

# Se non specifico nessun url esco
if [ -z "$dirdst" ]; then
   echo
   echo "[X] ERRORE: Inserire l'url del CMS Wordpress da scaricare e la directory di destinazione"
   echo "[ ] Esempio: $0 http://www.example.it website_offline"
   echo
   exit

fi

# Se esiste la directory di destinazione esco

if [ -d "$dirdst" ]; then

   echo "[X] ERRORE: Directory $dirdst esistente"
   exit

fi

echo "[*] Url: $url"
echo "[*] Dir: $dirdst"
echo "[*] Domain: $domain"
echo

# Funzione controllo connessione e certificato ssl
function CheckConn {
   cmdwget=""
   cmdwgetsslcheck="wget "
   cmdwgetnosslcheck="wget --no-check-certificate "

   cmdwget=$cmdwgetsslcheck

    if ! ERROR=$($cmdwget $url -O /dev/null 2>&1 >/dev/null); then

      checksslcert=$(echo $ERROR |grep "certificate")
      
      if [ -z "$checksslcert" ]; then
         echo "[X] ERRORE: Non riesco a collegarmi verso l'url $url"
         exit
      else
         while true; do
            read -p "[?] ATTENZIONE: Il certificato SSL Non sembra essere valido, vuoi continuare? (S/N) " sn
            case $sn in
               [Ss] ) cmdwget=$cmdwgetnosslcheck; break;;
               [Nn] ) echo "[!] Download sito interrotto dall'utente."; exit;;
               * ) echo "Rispondere S o N";;
            esac
         done
      fi

   fi
}

# Eseguo funzione controllo connessione e certificato ssl
CheckConn

# Scarico l'intero sito e converto i link con i paths relativi
$cmdwget -m --html-extension --convert-links --domains $domain --no-parent $url -P $dirdst 2>/dev/null &
pid=$!

spin='-\|/'

i=0
while kill -0 $pid 2>/dev/null
do
  i=$(( (i+1) %4 ))
  printf "\r[+] Download in corso del sito $url ${spin:$i:1}"
  sleep .1
done
echo

# Se la variabile yoast e' attiva scarico la sitemap e correggo i canonical links
if [ "$yoast" == "1" ]; then

   echo "[+] Download in corso della sitemap YOAST ...."

   # Genero sitemap YOAST Plugin
   $cmdwget -m $url/index.php/sitemap_index.xml -P $dirdst &>/dev/null
   $cmdwget -m $url/index.php/post-sitemap.xml -P $dirdst &>/dev/null
   $cmdwget -m $url/index.php/category-sitemap.xml -P $dirdst &>/dev/null
   $cmdwget -m $url/index.php/post_tag-sitemap.xml -P $dirdst &>/dev/null

   # Entro nella cartella del sito scaricato
   cd $dirdst/$domain/

   echo "[+] In accordo con le specifiche SEO modifico i file per rimuovere errori ...."

   # Sostituisco il contenuto del link rel canonical con il contenuto dell'attributo og:url
   # in accordo con le regole SEO (YOAST Plugin).
   for indexfile in $(find . -name "*.html*"); do

      # Estrapolo og:url
      ogurl=$(cat $indexfile| grep "og:url" | sed -n '1p' |  sed -e 's/.*content="\(.*\)".*/\1/')

      # Estrapolo canonical
      canonical=$(cat $indexfile | grep "<link rel=\"canonical\"" | sed -n '1p' |  sed -e 's/.*href="\(.*\)".*/\1/')

      # Creo nuova linea canonical
      canonicalnew=$(cat $indexfile | grep "<link rel=\"canonical\"" | sed -n '1p' | sed 's,'"$canonical"','"$ogurl"',')

      # Conto il numero riga del vecchio canonical da sostituire
      linea=$(grep -n "<link rel=\"canonical\"" $indexfile | sed -n '1p' | cut -d":" -f1)

      # Aggiungo nuova riga canonical
      sed -i "$linea a\\$canonicalnew" $indexfile

      # Rimuovo vecchia riga canonical
      sed -i "${linea}d" $indexfile

   done
   
   # Popolo il file .htaccess con alcuni rewrite url necessari
   htaccess="RewriteRule ^sitemap_index.xml$ /index.php/sitemap_index.xml [L]\n"
   htaccess+="RewriteRule ^sitemap.xsl$ /index.php/sitemap_index.xml [L]\n"
   htaccess+="RewriteRule ^sitemap.xml$ /index.php/sitemap_index.xml [L]"

else
   # Entro nella cartella del sito scaricato
   cd $dirdst/$domain/
fi

echo "[+] Download in corso Feed RSS ...."

# Scarico l'rss feed
rm -rf ./index.php/feed/*
$cmdwget -q $url/index.php/feed/ -O ./index.php/feed/index.xml 2> /dev/null

echo "[+] Rinomino tutti i files in maniera corretta ...."

# Rinomino tutti i files in maniera corretta (rimuovo numero versione dal nome file)
for filemv in $(find . -name *\?v*=*); do mv $filemv $(echo $filemv | cut -d"?" -f1); done

echo "[+] Edito tutti i files e converto il codice URLencode \"%3Fv\" in \"?v\" ...."

# Edito tutti i files e converto il codice URLencode "%3Fv" in "?v"
for filedit in $(grep "%3Fv" . -R | cut -d ":" -f1); do sed -i -e 's/%3Fv/?v/g' $filedit; done

echo "[+] Creo file .htaccess ...."

# Creo file .htaccess in modo da redirigere la sitemap, la pagina index.php, il feed RSS, ecc...
cat << EOF > .htaccess

<IfModule mod_rewrite.c>
RewriteEngine On
RewriteBase /

$(echo -e $htaccess)

RewriteRule ^index.php/feed/$  /index.php/feed/index.xml [L]
RewriteRule ^index.php/feed/index.html$ /index.php/feed/index.xml [L]

RewriteRule ^index.php/$ $url/index.html [L]
</IfModule>
EOF

echo "[*] Download website $url COMPLETATO!"
