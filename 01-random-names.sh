curl -k https://reqres.in/api/users?page=1 2>/dev/null | grep -o '"*_name": *"[^"]*"' | grep -o '"[^"]*"$' | awk  '{ gsub(/\"|,|\s/,""); printf ("%s\n", $0) }' | awk 'ORS=NR%2?FS:RS'
