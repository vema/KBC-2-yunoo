#
# Awk script to convert KBC to ING format (Yunoo)
#
# Reads in KBC file - make sure the ',' are not used in the fields themselves
# writes to CSV ING style file
#
#----------------------------------------------------
#  Uitleg/Bevindingen bij formaat van KBC
#
#  Separator is ';' EN (goed nieuws) dit karakter komt niet voor in 1 van de velden
#  Er is een header aanwezig (alhoewel incompleet want de bedragen/saldi zijn opgesplitst in 2 kol)
#  Kolom Rekeningnummer(1) is in IBAN formaat
#  Kolom Rubrieknaam(2) is niet ingevuld
#  Kolom Naam(3) bevat altijd de naam van de rekeninghouder
#  Kolom Munt (4) bevat altijd EUR maar kan waarschijnlijk ander waarden bevatten. Dit houdt mogelijk problemen in ivm interpratie van bedrag/saldo indien dit het geval is.
#  Kolom Afschriftnummer(5) bevat een volgnummer dat aanduid op welk afschrift deze transactie vermeld werd. - nutteloze info voor yunoo
#  Kolom Datum(6) is de datum van de verrichting
#  Kolom Omschrijving(7) bevat gedetailleerde info over de transactie - ook de begunstigde.
#  Kolom Valuta(8) is de valutadatum - niet nodig voor yunoo
#  Kolom Bedrag(9) is het bedrag van de transactie gesplitst over 2 kolommen (geheel en centiemen)
#  Kolom Saldo(11) is het saldo na de verrichting. Ook gesplitst over 2 kolommen zoals Bedrag.
#

#
#  Initialisatie en zo
#
BEGIN {
	# Field separator of input file
	FS=";"
	# Header for the generic file
	Header = "\"Datum\",\"Begunstigde\",\"Rekening\",\"Tegenrekening\",\"Mutatiecode\",\"Af/Bij\",\"Bedrag\",\"Mutatiesoort\",\"Mededelingen\n"
	printf ("%s", Header)
}

# Zoekt de tegenrekening op
function tegenrekening( instr ) {
	switch(instr) {
		# Usual format 000-1234567-89
		case /[[:digit:]]+-[[:digit:]][[:digit:]][[:digit:]]+-[[:digit:]][[:digit:]]/:
			pos=match(instr, /[[:digit:]]+-[[:digit:]][[:digit:]][[:digit:]]+-[[:digit:]][[:digit:]]/, nr)
			#print "REG: "  pos " - " nr[0]
			return "\"" nr[0] "\""
		# IBAN format
		case /[[:alpha:]][[:alpha:]][[:digit:]][[:digit:]] [[:digit:]][[:digit:]][[:digit:]][[:digit:]]/:
			pos = match(instr, /[[:alpha:]][[:alpha:]][[:digit:]]+ [[:digit:]][[:digit:]][[:digit:]][[:digit:]] [[:digit:]][[:digit:]][[:digit:]][[:digit:]] [[:digit:]][[:digit:]][[:digit:]][[:digit:]]/, nr)
			#print "IBAN:" pos "-" nr[0]
			if (pos >= 0) {
				return "\"" nr[0] "\""
			}
			# fall thru naar default indien pos 0 is (of kleiner)
		# other
		default:
			tegrek = "\"000-0000000-00\""
			return tegrek
	}
}

# Zet de datum om in formaat voor ING
function datum_omrekenen (instr) {
	split(substr(instr,2,10),dat,"/")
	date=sprintf("\"%d%02d%02d\"", strtonum(dat[3]), strtonum(dat[2]), strtonum(dat[1]))
	return date
}

# Zet het bedrag om naar absolute cijfers met een komma tussen eenheden en centiemen
function bedrag_berekenen(bedrag, centiemen) {
	if (bedrag <0) {
		bedrag=-(bedrag-centiemen/100)
	} else {
		bedrag=bedrag+centiemen/100
	}
	# maak er een getal van met 2 cijfers na de komma
	tb=sprintf("%.2f",bedrag)
	# en vervang de '.' door een ','
	split(tb,res,".")
	bedr=res[1] "," res[2]
	return bedr
}

#
# Haalt de begunstigde uit de omschrijving
#
function begunstigde (instr) {
	#print instr
	switch(instr) {
		case /BETALING AANKOPEN/:
			result = match(instr, /BETALING (.+) UUR, (.+) MET/, res)
			return "\"" res[2] "\""
		case /BETALING GEDOMICILIEERDE FACTUUR/:
			result = match(instr, /BETALING GEDOMICILIEERDE FACTUUR (.+) DOMICILIERINGSNUMMER [[:digit:]{3}]/, res)
			return "\"" res[1] "\""
		case /BETALING TANKBEURT/:
			result = match(instr, /BETALING TANKBEURT (.+) UUR, (.+) MET/, res)
			return "\"" res[2] "\""
		case /EUROPESE OVERSCHRIJVING NAAR /:
			result = match(instr, /EUROPESE OVERSCHRIJVING NAAR (.+) BEGUNSTIGDE: ([[:alpha:]]+)/, res)
			return "\"" res[2] "\""
		case /GELDOPNEMING/:
		case /[EUROPESE ]?OVERSCHRIJVING VAN/:
		case /PROTON/:
			return "\"" "MEZELF" "\""
		case /EUROPESE PERIODIEKE OPDRACHT OVERSCHRIJVING /:
			result = match(instr, /EUROPESE PERIODE OPDRACHT OVERSCHRIJVING NAAR (.+) BEGUNSTIGDE: ([[:alpha:]]+)/, res)
			return "\"" res[2] "\""
		case /PERIODIEKE OPDRACHT OVERSCHRIJVING /:
			result = match(instr, /PERIODIEKE OPDRACHT OVERSCHRIJVING NAAR ([[:digit:]][[:digit:]][[:digit:]]-[[:digit:]][[:digit:]][[:digit:]][[:digit:]][[:digit:]][[:digit:]][[:digit:]]-[[:digit:]][[:digit:]]) ([[:alnum:][:punct:]]+)/, res)
			print "PERIODIEKE OPDRACHT OVERSCHRIJVING " result " - " res[1] " - " res[2]
			return "\"" res[2] "\""
		case /OVERSCHRIJVING NAAR/:
			result = match(instr, /OVERSCHRIJVING NAAR ([[:digit:]][[:digit:]][[:digit:]]-[[:digit:]][[:digit:]][[:digit:]][[:digit:]][[:digit:]][[:digit:]][[:digit:]]-[[:digit:]][[:digit:]]) ([[:alnum:][:punct:]]+)/, res)
			return "\"" res[2] "\""
		default:
			return "\"????\""
	}
}

# Only work with lines that start with a bank account number
/"?[[:upper:]][[:upper:]][[:digit:]][[:digit:]][[:digit:]][[:digit:]].*/ {
	datum=datum_omrekenen($6)
	rekening=("\"" substr($1,6,length($1)-2))
	mutatiecode="\"\""
	mededelingen=substr($7,1,length($7)-1)
	mutatiesoort="\"\""
	# veld 9: geheel gedeelte van bedrag
	# veld 10: centiemen
	bedr=bedrag_berekenen($9,$10)
	if ($9 < 0) {
		afbij="\"Af\""
	} else {
		afbij="\"Bij\""
	}
	aan=begunstigde($7)
	
	printf("%s,%s,%s,%s,%s,%s,\"%s\",%s,%s\n",
		datum,aan,rekening,tegenrekening($7),mutatiecode,afbij,
		bedr,mutatiesoort,mededelingen)
}
