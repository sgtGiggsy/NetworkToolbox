##############################################################################
##############################################################################
######                                                                  ######
######                                                                  ######
######                        NETWORK TOOLBOX                           ######
######                                                                  ######
######    Röviden a program általános hálózati és/vagy rendszergazdai   ######
######      feladatok ellátásában nyújt segítséget. Ilyenek például:    ######
######          - egy eszköz helyének megkeresése a hálózaton           ######
######          - egy OU minden gépének megkeresése a hálózaton         ######
######          - egy IP tartomány minden eszközének megkeresése        ######
######          - egy felhasználó jelenlegi gépnevének megtalálása      ######
######          - egy OU végigpingelése                                 ######
######          - egy IP tartomány végigpingelése                       ######
######          - tömeges parancsfuttatás switcheken                    ######
######          - tömeges adatkinyerés switchekről táblázatba           ######
######     A program korábban már nagyjából késznek volt tekinthető     ######
######        aztán néhány változtatás működésképtelenné tette és       ######
######   a hanyag dokumentációmnak köszönhetően most majdnem nulláról   ######
######       kell felépíteni újra. Remélhetőleg most már tisztább,      ######
######           szebb és átláthatóbb kód lesz a végeredmény            ######
######                                                                  ######
######    Fejlesztési tervek:                                           ######
######      - bugfixek (folyamatban)                                    ######
######      - képessé tenni tömeges switch automatizálásra (pl mentés)  ######
######      - képessé tenni adatkinyerésre switchekből táblázatba       ######
######      - képessé tenni VLANok közti traceroute-ra is               ######
######                                                                  ######
##############################################################################
##############################################################################

###################################################################################################
###                                        SCRIPT VARS                                          ###
###################################################################################################

$ErrorActionPreference = "Stop"

$Script:config = @{
    ### Alapbeállítások ###
    varakozasbevitelre = 5
    dbfile = "NetworkToolbox"
    debug = $False
    csvkonyvtar = ".\Logfiles"
    csvin = ".\switchlist.csv"

    ### Logolás ###
    logging = $True
    loglevel = 0
    logfile = "nettoolbox.log"
    logfolder = ".\Logfiles"

    ### Programspecifikus ###
    nevgyujtes = $True
    logonline = $True
    logoffline = $True
    tftp = "tftpIP"
    switch = "switchip"
    fileserver = "fileszervernév"
    ounev = "alapértelmezett"
    port = 23
    method = 1
    waittime = 500
    maxhiba = 4
    retrytime = 15
    aktivnapok = 180
    csvnevelotag = "Geplista"

    ### Bemenet OU-k ###
    ou1nev = "Az egyes OU menüben megjelenő neve"
    ou1path = "az.egyes.ou/elérési/útja"
    ou2nev = "A kettes OU menüben megjelenő neve"
    ou2path = "a.kettes.ou/elérési/útja"
    ou3nev = $False
    ou3path = $False
    ou4nev = $False
    ou4path = $False
    ou5nev = $False
    ou5path = $False
    ou6nev = $False
    ou6path = $False
    ou7nev = $False
    ou7path = $False
    ou8nev = $False
    ou8path = $False
}

$Script:runtime = @{
    sql = $null
    cred = $null
    pingoptions = $null
    admin = $False
    adavailable = $False
}

### Hashtable ###
$logEvents = @{
    command = "PARANCS KIADVA"
    begin = "FOLYAMAT MEGKEZDŐDÖTT"
    end = "FOLYAMAT VÉGETÉRT"
    err = "HIBA"
    warn = "FIGYELMEZTETÉS"
    denied = "HOZZÁFÉRÉS MEGTAGADVA"
    ouisset = "OU KIVÁLASZTVA"
    fileerr = "CSV HIBA"
    conferr = "CONFIG.INI HIBA"
    down = "OFFLINE"
    up = "ONLINE"
    mail = "MAIL KÜLDVE"
    mailerr = "MAIL HIBA"
    missingdll = "HIÁNYZÓ DLL"
    noadserver = "NINCS ELÉRHETŐ DOMAIN CONTROLLER"
    success = "SIKER"
    timeout = "IDŐTÚLLÉPÉS"
    autherr = "HITELESÍTÉSI HIBA"
    loginerr = "BEJELENTKEZÉSI HIBA"
    unreachable = "ESZKÖZ NEM ELÉRHETŐ"
    conerr = "KAPCSOLÓDÁSI HIBA"
    consuccess = "SIKERES KAPCSOLÓDÁS"
    ipmatch = "IP CÍM AZONOSSÁG"
    devnamematch = "GÉPNÉV AZONOSSÁG"
    routeerr = "ÚTVONAL HIBA"
    arperr = "ARP TÁBLA HIBA"
    devstate = "ESZKÖZ ÁLLAPOT"
    founduser = "FELHASZNÁLÓ MEGTALÁLVA"
    searcherr = "SIKERTELEN KERESÉS"
    datasourceerr = "ADATFORRÁS HIBA"
    notmatchingsub = "ELTÉRŐ ALHÁLÓZATOK"
    dbwriteerr = "ADATBÁZIS ÍRÁSI HIBA"
}

###################################################################################################
###                            IMPORTÁLT FÜGGVÉNYEK ÉS OSZTÁLYOK                                ###
###################################################################################################

# Ebben a részben a más scriptekhez megírt, újrafelhasznált függvények
# és osztályok találhatóak. Ezek változtatás nélkül kerültek be ide.
# NEM PISZKÁLNI ŐKET!!!

#-#-#-#-#-#-#-#-#-#-#-#-#-#-#-#-#-#-#-#-#-#-#-#-#-#-#-#-#-#-#-#-#-#-#-#-#-#-#-#-#-#-#-#-#-#-#-#-#-#
#-#-#                                     OSZTÁLYOK                                           #-#-#
#-#-#-#-#-#-#-#-#-#-#-#-#-#-#-#-#-#-#-#-#-#-#-#-#-#-#-#-#-#-#-#-#-#-#-#-#-#-#-#-#-#-#-#-#-#-#-#-#-#

Class Time
{
    # Általános idő műveletek, mert lusta vagyok megtanulni a formátumot rájuk
    $filetime

    Time()
    {
        [string]$this.filetime = Get-Date -Format "yyyyMMdd_HHmm"
    }
    Static [String]Stamp()
    {
        Return Get-Date -Format "yyyy.MM.dd HH:mm"
    }

    Static [String]FileDate()
    {
        Return Get-Date -Format "yyyyMMdd_HHmm"
    }

    [String]FileName()
    {
        Return $this.filetime
    }
}

Class SQL
{
    $con

    SQL()
    {
        ## Kapcsolat létrehozása
        Import-Module .\System.Data.SQLite.dll
        $dataSource = "$($Script:config.dbfile).db"
        $this.con = New-Object -TypeName System.Data.SQLite.SQLiteConnection
        $this.con.ConnectionString = "Data Source=$dataSource"
        $this.Close()
    }

    Open()
    {
        ## Kapcsolat megnyitása
        try {
            $this.con.Open()
        } catch { }
    }

    CreateTable($dbname, $attribvaluehash)
    {
        ## Adattábla létrehozása
        $i = 1
        $c = $attribvaluehash.Count
        $commandtext = "CREATE TABLE IF NOT EXISTS $dbname (`n"
        foreach($attrib in @($attribvaluehash.Keys))
        {
            $commandtext += "$attrib "
            if($i -ne $c)
            {
                $commandtext += "$($attribvaluehash[$attrib]),`n"
            }
            else
            {
                $commandtext += "$($attribvaluehash[$attrib])`n);"
            }
            $i++
        }
        $this.UpdateDatabase($commandtext)
        $this.Close()
    }

    DropTable($tabletodrop)
    {
        $commandtext = "DROP TABLE $tabletodrop"
        $this.UpdateDatabase($commandtext)
        $this.Close()
    }

    AddRecord($commandtext, $attribname, $value)
    {
        ## Új sor hozzáadása
        $sql = $this.RunCommand($commandtext)
        for ($i = 0; $i -lt $attribname.Length; $i++)
        {
            if(!$value[$i])
            {
                $ertek = "null"
            }
            else
            {
                $ertek = $value[$i]
            }
            $sql.Parameters.AddWithValue($attribname[$i], $ertek) > $null
        }
        $sql.ExecuteNonQuery()
        $this.Close()
    }

    UpdateDatabase($commandtext)
    {
        $sql = $this.RunCommand($commandtext)
        $adapter = New-Object -TypeName System.Data.SQLite.SQLiteDataAdapter $sql
        $data = New-Object System.Data.DataSet
        try
        {
            [void]$adapter.Fill($data)
        }
        catch
        {
            Show-Debug $commandtext
            Out-Result -Text "Adatbázis írási hiba!" -Tag "dbwriteerr" -Level "err"
        }
        
        $this.Close()
    }

    [Object]QueryTable($commandtext)
    {
        $sql = $this.RunCommand($commandtext)
        $adapter = New-Object -TypeName System.Data.SQLite.SQLiteDataAdapter $sql
        $data = New-Object System.Data.DataSet
        try
        {
            [void]$adapter.Fill($data)
        }
        catch
        {
            Show-Debug $commandtext
            Out-Result -Text "Adatbázis írási hiba!" -Tag "dbwriteerr" -Level "err"
        }
        
        $this.Close()
        return $data.Tables
    }

    [Object]RunCommand($commandtext)
    {
        $this.Open()
        $sql = $this.con.CreateCommand()
        $sql.CommandText = $commandtext
        return $sql
    }

    Static [String]SetTableName($ObjType, $EgyediNev)
    {
        $SQLtableName = "$($ObjType)List_$($EgyediNev)"
        $SQLtableName.Replace(" ","_") > $null # Kicseréljük a szóközöket, hogy ne okozzanak problémát a táblaneveknél, a $null nélkül ezt is berakja a visszaadott listába

        Return $SQLtableName
    }

    Close()
    {
        $this.con.Close()
    }
}

Class MenuElem
{
    $Nev
    $Admin
    $ActiveDirectory
    $Call

    MenuElem($Nev, $Admin, $ActiveDirectory, $Call)
    {
        $this.Nev = $Nev
        $this.Admin = $Admin
        $this.ActiveDirectory = $ActiveDirectory
        $this.Call = $Call
    }

    MenuElem($Nev, $Call)
    {
        $this.Nev = $Nev
        $this.Call = $Call
    }

    MenuElem($Nev)
    {
        $this.Nev = $Nev
    }
}

#-#-#-#-#-#-#-#-#-#-#-#-#-#-#-#-#-#-#-#-#-#-#-#-#-#-#-#-#-#-#-#-#-#-#-#-#-#-#-#-#-#-#-#-#-#-#-#-#-#
#-#-#                                    FÜGGVÉNYEK                                           #-#-#
#-#-#-#-#-#-#-#-#-#-#-#-#-#-#-#-#-#-#-#-#-#-#-#-#-#-#-#-#-#-#-#-#-#-#-#-#-#-#-#-#-#-#-#-#-#-#-#-#-#

#### Alap függvények ####
#   Ezek a függvények   #
##   biztos kellenek   ##
#########################

##### FRISSÍTVE #####
function Initialize-Basics
{
    ###############################################################
    #
    # Leírás:       Lusta vagyok. Ez a függvény hívja meg a többi inicializálást igénylő alap függvényt,
    #               hozza létre a Logfiles mappát, hogy ne az Add-Log függvénynek kelljen.
    #
    # Bemenet:      -ADEssential:   kapcsoló, kiválasztásával megadhatjuk, hogy a script futhat-e AD nélkül
    #               -Admin:         kapcsoló, kiválasztásával megadhatjuk, hogy a script ellenőrizze-e az admin jog meglétét
    #
    # Függőségek:   * Read-Ini
    #               * Add-Log
    #               * Out-Result
    #               * Get-Userlevel
    #
    ###############################################################

    param(
        [Switch]$ADEssential,
        [Switch]$Admin
    )

    ### INI fájl beolvasása
    Read-Ini

    ### Admin jog ellenőrzése
    if($Admin -and (Get-Command 'Get-UserLevel' -errorAction SilentlyContinue))
    {
        $script:runtime.admin = Get-UserLevel
    }
    ### Logolás bekapcsoltságának ellenőrzése
    if(!$Script:config.logging)
    {
        Out-Result -Text "Figyelem logolás kikapcsolva!" -Level "warn"
    }

    ### Logfiles mappa meglétének ellenőrzése, és szükség szerint mappa létrehozása
    if (!(Test-Path $Script:config.logfolder)) # Ha nincs Logfiles mappa, létrehozzuk
    {
        $rootpath = (($Script:config.logfolder).Split("\Logfiles"))[0] # A logfolder változó utolsó tagját levágjuk, hogy megkapjuk a gyökerét
        New-Item -Path $rootpath -Name "Logfiles" -ItemType "Directory" | Out-Null
    }

    ### Ha a scriptben van Initialize-ADmodule függvény, kísérletet tesz a meghívására
    if (Get-Command 'Initialize-ADmodule' -errorAction SilentlyContinue)
    {
        if ($ADEssential)
        {
            $script:runtime.adavailable = Initialize-ADmodule -Essential > $null
        }
        else
        {
            $script:runtime.adavailable = Initialize-ADmodule
        }
    }
    elseif ($ADEssential)
    {
        Exit
    }

    ### Ha a scriptben van SQL osztály, kísérletet tesz az SQLite DLL importálására
    if ("SQL" -as [type])
    {
        try
        {
            Import-Module .\System.Data.SQLite.dll
        }
        catch # Ha van SQL osztály, akkor csak alapvető fontosságú lehet, így DLL hiba esetén a program kilép
        {
            Out-Result -Text "A System.Data.SQLite.dll hiányzik a telepítési könyvtárból! A program kilép!" -Level "err" -Tag "missingdll"
            Get-Valasztas
            Exit
        }
        
        ### Ha van SQL osztály, és elérhető a DLL, létrehozzuk az SQL objektumot
        $script:runtime.sql = [SQL]::New()
    }
}

##### FRISSÍTVE #####
function Read-Ini
{
    ###############################################################
    #
    # Leírás:       INI fájlok tartalmának beolvasása. A függvény beolvassa a mellékelt INI-t,
    #               és megpróbálja a benne lévő beállításokkal felülírni a script azonos nevű beállításait.
    #               Csak azokat a beállításokat írja felül, amihez talál párt a fájlban.
    #
    # Bemenet:      Nincs
    #
    # Függőségek:   Nincs
    #
    ###############################################################

    try
    {
        $config = Get-Content ".\config.ini" | Out-String | ConvertFrom-StringData
    }
    catch [System.ArgumentException]
    {
        Write-Host "HIBA A KONFIGURÁCIÓS FÁJLBAN!" -ForegroundColor Red
        Write-Host "Valószínűleg hiányzik egy \ jel valahonnan, ahol kettőnek kellene lennie egymás mellett" -ForegroundColor Yellow
        Read-Host
    }
    catch
    {
        Write-Host "A KONFIGURÁCIÓS FÁJL HIÁNYZIK! A PROGRAM AZ ALAPÉRTELMEZETT BEÁLLÍTÁSOKKAL FOG FUTNI!" -ForegroundColor Red
        Read-Host
    }

    foreach($elem in @($config.Keys)) # Végigmegyünk a fájl teljes tartalmán
    {
        if ($config[$elem] -eq "True") # A fájlból vett True értékű sztringet valódi $True-ra konvertáljuk
        {
            $config[$elem] = $true
        }
        elseif ($config[$elem] -eq "False") # A fájlból vett False értékű sztringet valódi $False-ra konvertáljuk
        {
            $config[$elem] = $false
        }

        foreach($defconf in $Script:config.Keys) # Végigmegyünk az összes beállításon
        {
            if($elem -eq $defconf) # Ellenőrizzük, hogy a fájlból vett beállítás megfelel-e a script egy beállításának
            {
                if($null -ne $config[$elem]) # Ha a fájlból vett érték NULL, úgy a script beállítása nem kerül felülírásra
                {
                    if(($null -ne $Script:config[$defconf]) -and ($Script:config[$defconf].GetType() -eq [Int])) # Ha a beállítás [Int] úgy konvertáljuk az ini-ből vettet
                    {
                        $config[$elem] = [Int]$config[$elem]
                    }
                    $Script:config[$defconf] = $config[$elem] # Felülírjuk a script beállítását a fájlból vett értékkel
                }
                Break # Ha sikerült megfeleltetni egy fájlból vett beállítást a script egy beállításával, elhagyjuk a ciklust
            }
        }
    }
}

####### MÉG CSAK TERV, NINCS MEGÍRVA!!!!
function Write-Ini
{
    param ()
}

##### FRISSÍTVE #####
function Send-Mail
{
    ###############################################################
    #
    # Leírás:       Mailküldő függvény. A beállításokat az INI fájlból, vagy a script elejéből veszi
    #               
    # Bemenet:      -Subject:       a levél tárgya, kötelező megadni
    #               -Mailbody:      a levél szövege, kötelező megadni
    #               -Attachment:    a levél csatolmánya, nem kötelező megadni
    #               -Surgos:        kapcsoló, amennyiben a levelet sürgősnek jelölnénk meg
    #
    # Függőségek:   Out-Result
    #               Mail szekció megléte a beállítások részben
    #
    ###############################################################

    param (
        [Parameter(Mandatory=$true, ValueFromPipeline=$true)]$Subject,
        [Parameter(Mandatory=$true, ValueFromPipeline=$true)]$Mailbody,
        [Parameter(Mandatory=$false, ValueFromPipeline=$true)]$Attachment,
        [Switch]$Surgos
    )

    Begin
    {
        $password = ConvertTo-SecureString -String $Script:config.mailpass -AsPlainText -Force
        $cred = New-Object -TypeName System.Management.Automation.PSCredential -ArgumentList $Script:config.mailuser, $password
    }
    
    Process
    {
        try
        {
            if($Surgos)
            {
                if($Attachment)
                {
                    Send-MailMessage -From $Script:config.mailfrom -To $Script:config.mailto -Subject $Subject -Body $Mailbody -Attachments $Attachment -SmtpServer $Script:config.mailserver -Credential $cred -Port $Script:config.mailport -Encoding Unicode -Priority High
                }
                else
                {
                    Send-MailMessage -From $Script:config.mailfrom -To $Script:config.mailto -Subject $Subject -Body $Mailbody -SmtpServer $Script:config.mailserver -Credential $cred -Port $Script:config.mailport -Encoding Unicode -Priority High
                }
            }
            else
            {
                if($Attachment)
                {
                    Send-MailMessage -From $Script:config.mailfrom -To $Script:config.mailto -Subject $Subject -Body $Mailbody -Attachments $Attachment -SmtpServer $Script:config.mailserver -Credential $cred -Port $Script:config.mailport -Encoding Unicode
                }
                else
                {
                    Send-MailMessage -From $Script:config.mailfrom -To $Script:config.mailto -Subject $Subject -Body $Mailbody -SmtpServer $Script:config.mailserver -Credential $cred -Port $Script:config.mailport -Encoding Unicode
                }
            }
            Out-Result -Text "Értesítő mail elküldve $($Script:config.mailto) részére" -Level "green" -Tag "mail"
        }
        catch
        {
            Out-Result -Text "Mail küldése $($Script:config.mailto) részére sikertelen" -Level "err" -Tag "mailerr"
        }
    }
    
}

##### ÚJ
function Show-Menu
{
    ###############################################################
    #
    # Leírás:       Menü megjelenítő függvény. Vesz egy [MenuElem] objektumokat tartalmazó ArrayListet,
    #               és megjeleníti a tartalmát attól függően, hogy az adott menüelemekre
    #               milyen jogosultságok lettek beállítva.
    #               A Kilépés és a Visszalépés az előző menübe menüpontok külön billentyűkre kerültek,
    #               így összesen 11 (9 + a Kilépés/Visszalépés) menüelem megjelenítésére van mód.
    #               A függvény az első 9 megjeleníthető menüpontot jeleníti meg, az utána következőeket
    #               egyszerűen levágja hibaüzenet, vagy figyelmeztetés nélkül.
    #               A 9 menüpontos korlátra a Get-Valasztas miatt van szükség, mivel az csak egy karaktert
    #               fogad el bemenetnek.
    #               
    # Bemenet:      -Menu:      A menüelemeket tartalmazó ArrayList, nem kötelező megadni
    #               -Exit:      Kapcsoló, amellyel megadhatjuk, hogy utolsó elemként bekerüljön-e a Kilépés menüpont
    #               -BackOne:   Kapcsoló, amellyel megadhtajuk, hogy utolsó (vagy -Exit esetén utolsó előtti) elemként bekerüljön-e a "Visszalépés az előző menübe" menüpont
    #               -Options:   Kapcsoló, amellyel megadhatjuk, hogy jelenjen meg a beállítások menüpont
    #               -JustShow:  Kapcsoló, amellyel megadhatjuk, hogy a függvény ne maga hívja meg a menü függvényeit
    #
    # Függőségek:   MenuElem osztály
    #               Get-Valasztas
    #
    ###############################################################

    param(
        [Parameter(Mandatory=$false)]$Menu,
        [Switch]$Exit,
        [Switch]$BackOne,
        [Switch]$Options,
        [Switch]$JustShow
    )

    $valasztastomb = $null
    $valasztastomb = @()
    if($Menu)
    {
        Write-Host "Válassz az alábbi menüpontok közül:"
        $i = 0
        $MenuToShow = $Menu.Clone() # Kell egy másolat, mert ForEach során nem lehet ArrayList-ekből törölni
        foreach ($menuitem in $Menu)
        {
            $additem = $false
            if($menuitem.Admin -or $menuitem.ActiveDirectory) # Ellenőrizzük, hogy az elemnek vannak-e jogosultság igényei
            {
                if(!$menuitem.Admin -and $menuitem.ActiveDirectory -eq $Script:runtime.adavailable)
                {
                    $additem = $true
                }
                elseif (!$menuitem.ActiveDirectory -and $menuitem.Admin -eq $Script:runtime.admin)
                {
                    $additem = $true
                }
                elseif ($menuitem.ActiveDirectory -eq $Script:runtime.adavailable -and $menuitem.Admin -eq $Script:runtime.admin)
                {
                    $additem = $true
                }
            }
            elseif ($i -lt 10) # Ha az elemnek nem kell plusz jogosultság, és 10-nél kevesebb menüpont van, hozzáadjuk a listához
            {
                $additem = $true
            }

            if($additem)
            {
                $i++
                Write-Host "($i) $($menuitem.Nev)"
                $valasztastomb += $i
            }
            else # Ha egy elem kiszűrésre került, kivesszük a kimenetnek használt ArrayList-ből
            {
                $MenuToShow.Remove($menuitem)
            }    
        }
    }

    if($Options)
    {
        Write-Host "(B) Beállítások"
        $valasztastomb += "B"
    }
    if($BackOne) # Ha szeretnénk, hogy legyen egy "Vissza" menüpont
    {
        Write-Host "(V) Visszalépés az előző menübe"
        $valasztastomb += "V"
    }
    if($Exit) # Ha szeretnénk, hogy legyen egy "Kilépés" menüpont
    {
        Write-Host "(K) Kilépés"
        $valasztastomb += "K"
    }

    Show-Debug $valasztastomb.Length
    if($valasztastomb.Length -gt 0) # Ha megadtunk bemenetet, annak kiiratása
    {
        $valaszt = Get-Valasztas $valasztastomb

        if($valaszt -eq "K")
        {
            Exit
        }
        elseif($JustShow)
        {
            Return $valaszt
        }
        elseif ($valaszt -eq "V") { }
        elseif ($valaszt -eq "B")
        {
            Update-Config    
        }
        else
        {
            if($MenuToShow[$valaszt-1].Call)
            {
                Invoke-Expression "$($MenuToShow[$valaszt-1].Call)" # Invoke-oljuk a stringben átadott függvényt
            }
        }
    }
    else # Bemenet nélkül szimpla "press key to continue" funkció ellátása (duplkikált funkció, csak lekezeltem az esetleges hibát ezzel)
    {
        Get-Valasztas
    }
}

##### FRISSÍTVE #####
function Out-Result
{
    ###############################################################
    #
    # Leírás:       Kiírató függvény. Lényegében a Write-Host felturbózott változata.
    #               Egyszerre gondoskodik a szöveg megjelenítéséről, és a logolásról is.
    #               Átláthatóbbá teszi, hogy egy szöveg új sorban jelenik-e meg,
    #               vagy felülírja-e az előző sort.
    #               
    # Bemenet:      -Text:      a nyers szöveg, kötelező megadni
    #               -Level:     a szövege szintje, lehet "err" a hibákhoz, "warn" a figyelmeztetésekhez, illetve "green", nem kötelező megadni
    #               -Tag:       a log bevezető cimkéje, ha nincs megadva, az üzenet nem logolódik
    #               -Overwrite: az előző sor felülírása, kapcsoló, nem kötelező megadni
    #               -NoNewLine: ugyanaz, mint a Write-Host esetében, kapcsoló, nem kötelező megadni
    #
    # Függőségek:   * Clear-Line
    #               * Add-Log
    #
    ###############################################################

    param (
        [Parameter(Mandatory=$true)]$Text,
        [Parameter(Mandatory=$false)]$Level,
        [Parameter(Mandatory=$false)]$Tag,
        [switch]$Overwrite,
        [switch]$NoNewLine
    )

    if(!$Tag -and ($Level -eq "err" -or $Level -eq "warn") -and $Script:config.loglevel -gt 0)
    {
        if($Script:config.loglevel -eq 1)
        {
            $Tag = $Level
        }
        elseif (($Script:config.loglevel -eq 2) -and ($Level -eq "err"))
        {
            $Tag = $Level
        }
    }

    if($Tag)
    {
        Add-Log -Tag $Tag -Text $Text
    }

    if($Overwrite)
    {
        Clear-Line
        $Text = "`r$Text"
    }

    switch($Level)
    {
        "err"
            {
                if($NoNewLine)
                {
                    Write-Host $Text -ForegroundColor Red -NoNewline
                }
                else
                {
                    Write-Host $Text -ForegroundColor Red
                }
            }
        "warn"
            {
                if($NoNewLine)
                {
                    Write-Host $Text -ForegroundColor Yellow -NoNewline
                }
                else
                {
                    Write-Host $Text -ForegroundColor Yellow
                }
            }
        "green"
            {
                if($NoNewLine)
                {
                    Write-Host $Text -ForegroundColor Green -NoNewline
                }
                else
                {
                    Write-Host $Text -ForegroundColor Green
                }
            }
        default
            {
                if($NoNewLine)
                {
                    Write-Host $Text -NoNewline
                }
                else
                {
                    Write-Host $Text
                }
            }
    }
}

##### FRISSÍTVE #####
function Add-Log
{
    ###############################################################
    #
    # Leírás:       Logoló függvény. Létrehozza a Logfiles mappát, egyesíti a cimkét és a szöveget,
    #               valamint ellátja a log eseményeket időbélyegzővel, és a logfileba menti.
    #               
    # Bemenet:      -Tag:       a log cimkéje, kötelező megadni
    #               -Text:      a log szövege, kötelező megadni
    #
    # Függőségek:   * logEvents hashtable
    #               * Time osztály
    #
    ###############################################################

    param (
        [Parameter(Mandatory=$true)]$Tag,
        [Parameter(Mandatory=$true)]$Text
        )

    if($Script:config.logging)
    {   
        $logtext = $logtext -Replace "`r","" # Ha a szövegben volt sorfelülírós parancs, kivágjuk

        $logtext = "[$($logEvents[$Tag])] $Text $([Time]::Stamp())"
        $logtext | Out-File "$($Script:config.logfolder)\$($Script:config.logfile)" -Append -Force -Encoding unicode
    }
}

function Clear-Line
{    
    ###############################################################
    #
    # Leírás:       Sor tartalmát törlő függvény
    #               
    # Bemenet:      Nincs
    #
    # Függőségek:   Nincs
    #
    ###############################################################

    Write-Host "`r                                                                             " -NoNewline
}

function Save-ToCSV
{
    ###############################################################
    #
    # Leírás:       Újabb lusta vagyok megtanulni függvény. A használata egyszerűbb,
    #               mint minden egyes alkalommal megadni az összes kapcsolót.
    #               
    # Bemenet:      -Path:      A CSV fájl útvonala, kötelező megadni
    #               -ToSave:    A CSV fájlba kiírni kívánt objektum
    #
    # Kimenet:      Nincs
    #
    # Függőségek:   Nincs
    #
    ###############################################################

    param(
        [Parameter(Mandatory=$true)]$Path,
        [Parameter(Mandatory=$true)]$ToSave
        )

    $ToSave | Export-CSV -encoding UTF8 -path $Path -NoTypeInformation -Append -Force -Delimiter ";"
}

####  AD függvények  ####
#     Függvények AD     #
##     feladatokhoz    ##
#########################

##### FRISSÍTVE #####
function Initialize-ADmodule
{
    ###############################################################
    #
    # Leírás:       Nem lenne muszáj, hogy ez függvény legyen, de így átláthatóbb
    #
    # Bemenet:      -Essential:     kapcsoló, megadható vele, hogy az AD modul hiánya esetén futhasson-e a script
    #
    # Kimenet:      Bool érték az AD modulok meglétéről és AD elérhetőségéről
    #
    # Függőségek:   * Out-Result
    #
    ###############################################################

    param([Switch]$Essential)

    $adavailable = $True
    if (!(Get-Module -ListAvailable -Name ActiveDirectory)) # Ellenőrizzük, hogy az AD modul telepítve van-e
    {
        
        # Ha az AD modul nincs telepítve, akkor kísérletet teszünk az AD dll-ek használatára
        try
        {
            Import-Module .\Microsoft.ActiveDirectory.Management.dll
            Import-Module .\Microsoft.ActiveDirectory.Management.resources.dll
        }
        catch
        {
            Out-Result -Text "Az AD modul nincs telepítve, és a kapcsolódó DLL-ek sem találhatóak" -Tag "missingdll" -Level "err"
            $adavailable = $False
        }
    }
    if($adavailable)
    {
        try
        {
            Get-ADUser teszt | Out-Null
        }
        catch #[Microsoft.ActiveDirectory.Management.ADServerDownException]
        {
            Out-Result -Text "A hálózaton nincs elérhető Active Directory kiszolgáló" -Level "warn" -Tag "noadserver"
            $adavailable = $false
        }
    }

    if(!$adavailable -and $Essential)
    {
        Out-Result -Text "Active Directory elérés nélkül a program nem képes futni! Üss Entert a program bezárásához!" -Level "err"
        Read-Host
        Exit
    }

    Return $adavailable
}

##### FRISSÍTVE #####
function ConvertTo-DistinguishedName
{
    ###############################################################
    #
    # Leírás:       DistinguishedName létrehozó függvény. A feladata, hogy a normál könyvtárjellegű OU nevet
    #               lefordítsa a tartományon belüli kereséshez használt distinguishedname formátumra.
    #               
    # Bemenet:      -OrganizationalUnit: az OU AD Users and Computersből vett elérési útja, kötelező megadni
    #
    # Kimenet:      DistinguishedName formátumú OU megnevezés
    #
    # Függőségek:   Nincs
    #
    # Funfact:      A legrégebbi totálisan változatlan, mai napig is használt függvényem
    #
    ###############################################################
    
    param([Parameter(Mandatory=$true)]$OrganizationalUnit) #OU name in the form you can find it in ADUC

    $kimenet = $OrganizationalUnit.Split("/") #Splitting the OU name by slash characters
    
    for ($i = $kimenet.Length-1; $i -gt -1; $i--) #Loop starts from the last section of the string array to put them to the front
    {
        if ($i -ne 0) #Do the conversion until we get to the DC part
        {
            if ($i -eq $kimenet.Length-1) # This conditional is used to get the OU name from the whole path, so we can use it as as folder, or filename
            {
                $Script:config.ounev = $kimenet[$i]
            }
            $forditott += "OU="+ $kimenet[$i]+","
        }
        else #Here's where we turn DC name into DistinguishedName format too
        {
            $dcnevold = $kimenet[$i]
            $dcnevtemp = $dcnevold.Split(".")
            for ($j = 0; $j -lt $dcnevtemp.Length; $j++)
            {
                if ($j -lt $dcnevtemp.Length-1) #It's needed so there won't be a comma at the end of the output
                    {
                        $dcnev += "DC="+$dcnevtemp[$j]+","
                    }
                else 
                    {
                        $dcnev += "DC="+$dcnevtemp[$j]
                    }    
            }
            $forditott += $dcnev
        }
    }    
    return $forditott #OU name in DistinguishedName form
}

##### FRISSÍTVE #####
function Test-OU
{
    ###############################################################
    #
    # Leírás:       OU létezését ellenörző függvény. Ha kap bemenetet, akkor azt ellenőrzi,
    #               ha nem, bekéri a felhasználótól. A bemenetet átadja a ConvertTo-DistinguishedName-nek,
    #               majd ellenőrzi, hogy az OU létezik-e. Ha a felhasználótól kéri be az adatot,
    #               addig fut, amíg helyes bemenetet kap, bemenő paraméter megléte esetén csak ellenőriz,
    #               és ha az OU nem létezik, $False értéket ad vissza.
    #               
    # Bemenet:      -OUToTest:      az ellenőrzendő OU AD Users and Computersből vett elérési útja, nem kötelező megadni
    #               -NoDistinguish: kapcsoló, kiválasztva a visszaadott OU nem DistinguishedName formátumban lesz
    #               -Users:         kapcsoló, kiválasztva a függvény teszteli, hogy vannak-e felhasználók az OU-ban
    #               -Computers:     kapcsoló, kiválasztva a függvény teszteli, hogy vannak-e számítógépek az OU-ban
    #               -Groups:        kapcsoló, kiválasztva a függvény teszteli, hogy vannak-e csoportok az OU-ban
    #
    # Kimenet:      Ellenőrzött, létező, valamint kapcsolók használata esetén
    #               garantáltan megfelelő objektumokat tartalmazó OU, normál vagy DistinguishedName formátumban
    #
    # Függőségek:   * ConvertTo-DistinguishedName
    #               * Out-Result
    #
    ###############################################################
    
    param(
        [Parameter(Mandatory=$false)]$OUToTest,
        [Switch]$NoDistinguish,
        [Switch]$Users,
        [Switch]$Computers,
        [Switch]$Groups
    )

    $loopcount = 1 # A változó, hogy maximálhassuk a próbálkozási ciklusok számát
    do 
    {
        $endloop = $false
        if(!$OUToTest) # Ha nincs bemeneti OU, itt kérjük be az útvonalát
        {
            Write-Host "Kérlek add meg a használni kívánt OU elérési útját!"
            $originalOUpath = Read-Host -Prompt "Elérési út"
        }
        else
        {
            $originalOUpath = $OUToTest
        }

        try # Meghívjuk a DistinguishedName fordítót, és ellenőrizzük, hogy az OU egyáltalán létezik-e
        {            
            $ou = ConvertTo-DistinguishedName $originalOUpath
            Get-ADOrganizationalUnit -Identity $ou | Out-Null
            $endloop = $true
        }
        catch
        {
            Out-Result -Text "A megadott OU nem létezik!" -Level "err"
            $ou = $False
            if($OUToTest) # Ha csak egy OU meglétét akartuk ellenőrizni a függvénnyel, akkor ki is léphetünk False eredménnyel
            {
                $endloop = $True
            }
            else
            {
                Out-Result -Text "Add meg újra az elérési utat!" -Level "err"
                $endloop = $False
            }
        }

        if($ou -and ($Users -or $Computers -or $Groups)) # Ha az OU létezik, és megadtunk kapcsolót, akkor objektumokat keresünk
        {
            if ($Users)
            {
                $job = Start-Job -ScriptBlock { Get-ADUser -SearchBase $args[0] -Filter * } -ArgumentList $ou
                $objlista = Show-JobInProgress -Text "A(z) $($Script:config.ounev) OU felhasználóinak megszámolása folyamatban" -Job $job
                $tipus = "felhasználók"
            }
            elseif ($Computers)
            {
                $job = Start-Job -ScriptBlock { Get-ADComputer -SearchBase $args[0] -Filter * } -ArgumentList $ou
                $objlista = Show-JobInProgress -Text "A(z) $($Script:config.ounev) OU számítógépeinek megszámolása folyamatban" -Job $job
                $tipus = "számítógépek"
            }
            elseif ($Groups)
            {
                $job = Start-Job -ScriptBlock { Get-ADGroup -SearchBase $args[0] -Filter * } -ArgumentList $ou
                $objlista = Show-JobInProgress -Text "A(z) $($Script:config.ounev) OU csoportjainak megszámolása folyamatban" -Job $job
                $tipus = "csoportok"
            }
            
            if($objlista.Length -eq 0)
            {
                Out-Result -Text "A megadott $($Script:config.ounev) OU-ban nincsenek $tipus" -Level "warn"
                $endloop = $False
            }            
        }
        if($loopcount -eq 3)
        {
            Out-Result -Text "Harmadszorra is érvénytelen, vagy keresett objektumot nem tartalmazó OU-t adtál meg.`nProgram Leáll" -Level "err"
            Read-Host
            Exit
        }
        $loopcount++ 
    } while (!$endloop)

    if($NoDistinguish -and $ou) # Ha nem DistinguishedName formátumot akarunk, akkor az eredeti útvonalat kell visszaadni
    {
        return $originalOUpath
    }
    else
    {
        return $ou
    }
}

##### FRISSÍTVE #####
function Select-OU
{
    ###############################################################
    #
    # Leírás:       OU kiválasztását elvégző függvény. A config fájlból vett ou[$i]nev és ou[$i]path
    #               kulcsokból egy listát készít, és felkínálja őket kiválasztásra.
    #               Első ránézésre talán bonyolultnak tűnik a működése, de a célja az,
    #               hogy rugalmas lehetőséget adjon a felhasználó kezébe. Ha csak 3 OU-t adunk meg
    #               a config fájlban, akkor csak három lehetőséget kínál fel a rendszer, ha 8-at, akkor nyolcat.
    #               Egy és nyolc bejegyzés között a függvény rugalmasan képes alkalmazkodni.
    #               Utolsó bejegyzésként mindig az OU kézi bevitele kerül a listába, így maximálisan 9 menüpont
    #               jeleníthető meg. Ha nagyon akarnám, lehetne több is, de ennyi bőven elegendőnek tűnik jelenleg.
    #                       !!! Jelen verzió az INI fájlból érkező bemenet helyességét NEM ellenőrzi !!!
    #               
    # Bemenet:      -NoDistinguish:  Kapcsoló, használatával nem DistinguishedName formátumot ad vissza a függvény
    #               -Users:          Kapcsoló, használatával a függvény ellenőrzi, hogy az OU-ban vannak-e felhasználók
    #               -Computers:      Kapcsoló, használatával a függvény ellenőrzi, hogy az OU-ban vannak-e számítógépek
    #               -Groups:         Kapcsoló, használatával a függvény ellenőrzi, hogy az OU-ban vannak-e csoportok
    #
    # Kimenet:      OU elérési út, sima, vagy DistinguishedName formátumban
    #
    # Függőségek:   * $Global.config.ou[sorsz]nev és Global.config.ou[sorsz]path változók megléte
    #               * Get-Valasztas - a lehetőségek kiválasztásához
    #               * Test-OU - a kézileg bevitt OU ellenőrzéséhez
    #               * Add-Log - a logoláshoz
    #
    ###############################################################
    
    param(
        [Switch]$NoDistinguish,
        [Switch]$Users,
        [Switch]$Computers,
        [Switch]$Groups
        )

    $alakulatok = @() # Tömb a Nev - Path attribútumokból álló OU objektumok tárolására
    
    for($i = 1; $i -le 8; $i++)
    {
        $ouToUse = New-Object psobject # Sima egyedi objektum, nincs szükség külön osztályra
        foreach($conf in $Script:config.Keys)
        {
            if ($conf -eq "ou$($i)nev")
            {
                if($Script:config[$conf]) # Ha nem False a talált érték, úgy hozzáadjuk az objektumhoz, ha False, elhagyjuk a belső ciklust
                {
                    $ouToUse | Add-Member NoteProperty -Name "Nev" -Value $Script:config[$conf]
                }
                else
                {
                    Break
                }
            }
            
            if ($conf -eq "ou$($i)path")
            {
                if($Script:config[$conf]) # Ha nem False a talált érték, úgy hozzáadjuk az objektumhoz, ha False, elhagyjuk a belső ciklust
                {
                    $ouToUse | Add-Member NoteProperty -Name "Path" -Value $Script:config[$conf]
                }
                else
                {
                    Break
                }
            }

            if($ouToUse.Nev -and $ouToUse.Path) # Ha mindkét attribútum beállításra került, ciklus vége
            {
                Break
            }
        }

        if($ouToUse.Nev) # Csak akkor adjuk hozzá az objektumot a tömbhöz, ha van is tartalma
        {
            $alakulatok += $ouToUse
        }
    }

    $ouToUse = New-Object psobject # Egyedi objektum a kézzel megadásos menüelem tömbhöz adásához
    $ouToUse | Add-Member NoteProperty -Name "Nev" -Value "OU megadása kézzel"
    $alakulatok += $ouToUse

    $i = 0;
    $valasztastomb = @() # Az engedélyezett választási lehetőségeket tartalmazó tömb
    Write-Host "Melyik OU-t szeretnéd lekérdezni?"
    foreach ($ou in $alakulatok)
    {
        $i++
        Write-Host "($i) $($ou.Nev)"
        $valasztastomb += $i
    }

    $valaszt = Get-Valasztas $valasztastomb -Idokorlat

    if($valaszt -eq $alakulatok.Count) # Ha az utolsó menüpontot választjuk, jöhet az adatbekérő függvény
    {
        if($NoDistinguish)
        {
            if($Users)
            {
                $ou = Test-OU -Users -NoDistinguish # A -Users kapcsolóval felhasználókra teszteli az OU-t
            }
            elseif($Computers)
            {
                $ou = Test-OU -Computers -NoDistinguish # A -Computers kapcsolóval számítógépekre teszteli az OU-t
            }
            elseif($Groups)
            {
                $ou = Test-OU -Groups -NoDistinguish # A -Groups kapcsolóval számítógépekre teszteli az OU-t
            }
            else
            {
                $ou = Test-OU
            }
        }
        else
        {
            if($Users)
            {
                $ou = Test-OU -Users # A -Users kapcsolóval felhasználókra teszteli az OU-t
            }
            elseif($Computers)
            {
                $ou = Test-OU -Computers # A -Computers kapcsolóval számítógépekre teszteli az OU-t
            }
            elseif($Groups)
            {
                $ou = Test-OU -Groups # A -Groups kapcsolóval számítógépekre teszteli az OU-t
            }
            else
            {
                $ou = Test-OU
            }
        }
    }
    else
    {
        if($NoDistinguish) # Ha a NoDistinguish kapcsoló True, fordítófüggvény meghívásának kihagyása
        {
            $ou = $alakulatok[$valaszt-1].Path
            $Script:config.ounev = $alakulatok[$valaszt-1].Nev
        }
        else 
        {
            $ou = ConvertTo-DistinguishedName -OrganizationalUnit $alakulatok[$valaszt-1].Path
        }
    }

    Add-Log -Text "$($Script:config.ounev) OU lekérdezésre kiválasztva" -Tag "ouisset"

    Return $ou
}

function Get-LoginCred
{
    ###############################################################
    #
    # Leírás:       Windows bejelentkezési objektumot létrehozó függvény. Bekéri a felhasználó
    #               felhasználónevét és jelszavát (a jelszót azonnal securestringként),
    #               majd PSCredential objektumot készít belőle
    #               
    # Bemenet:      Nincs
    #
    # Kimenet:      PSCredential objektum
    #
    # Függőségek:   Nincs
    #
    ###############################################################

    Write-Host "Kérlek add meg a felhasználóneved!"
    $felhasznalonev = Read-Host -Prompt "Felhasználónév"
    Write-Host "Kérlek add meg a jelszavadat!"
    $jelszo = Read-Host -AsSecureString -Prompt "Jelszó"
    $credentials = New-Object -TypeName System.Management.Automation.PSCredential -ArgumentList $felhasznalonev, $jelszo

    Return $credentials
}

## Folyamat függvények  ##
#  Függvények általános  #
## kezelési feladatokra ##
##########################

##### FRISSÍTVE #####
function Start-Wait
{
    ###############################################################
    #
    # Leírás:       Ez a függvény gondoskodik róla, hogy két futás között egy ciklus szünetet tartson.
    #               Mivel alapvetőleg két ciklus futása között valószínűleg nem telik el hosszabb idő,
    #               a megjelenítés legfeljebb pár percre képes.
    #               
    # Bemenet:      -Seconds:   a várakozás ideje másodpercben, kötelező megadni
    #
    # Kimenet:      Nincs
    #
    # Függőségek:   Clear-Host
    #
    ###############################################################
    
    param(
        [Parameter(Mandatory=$False)]$Seconds,
        [Parameter(Mandatory=$False)]$Minutes,
        [Parameter(Mandatory=$False)]$Hours,
        [Parameter(Mandatory=$False)]$Tomorrow,
        [Switch]$TillTime,
        [Switch]$SkipWeekend
    )

    if([bool]$Seconds + [bool]$Minutes + [bool]$Hours + [bool]$TillTime + [bool]$Tomorrow -eq 1)
    {
        if($Seconds)
        {
            $vissza = $Seconds
        }
        elseif($Minutes)
        {
            $vissza = ([TimeSpan]::FromMinutes($Minutes)).TotalSeconds
        }
        elseif($Hours)
        {
            $vissza = ([TimeSpan]::FromHours($Hours)).TotalSeconds
        }

        elseif($TillTime)
        {
            do # Ez a do-while ciklus addig fut, míg meg nem kapja a hét kiválasztott napjának dátumát
            {
                $inditas = (Get-Date).AddDays($nap)
                if($most.DayOfWeek -eq $Script:config.kezdonap) # Ha az indításként megadott nap megegyezik a mával
                {
                    if($most.Hour -lt $Script:config.kezdoora) # Ha az indításként megadott óra még nem jött el
                    {
                        $inditas = Get-Date
                    }
                    else
                    {
                        $inditas = (Get-Date).AddDays(7) # Ha az indítási nap megegyezik a mával, de az óra elmúlt, +1 hét
                    }
                }
                else
                {
                    $nap++
                    if ($nap -gt 7) # Ha a ciklus lefut 7-szer eredmény nélkül, úgy hibás a megadott nap neve, ami végtelen ciklust eredményezne
                    {
                        Write-Host "A config fájlban hibásan lett megadva a kezdési nap. Javítsd ki, majd futtasd újra a programot!" -ForegroundColor Red
                        Read-Host
                        Exit # A hibaüzenetet követően a program leáll
                    }
                }
            } while($inditas.DayOfWeek -ne $Script:config.kezdonap)

            $inditas = ($inditas.Date).AddHours($Script:config.kezdoora) # Megadjuk az indítás óráját
        }
        elseif($Tomorrow)
        {
            $most = Get-Date
            $inditas = (Get-Date).AddDays(1)
            if($SkipWeekend -and (($inditas.DayOfWeek -eq "Saturday") -or ($inditas.DayOfWeek -eq "Sunday")))
            {
                if($inditas.DayOfWeek -eq "Saturday")
                {
                    $inditas = $inditas.AddDays(2)
                }
                else
                {
                    $inditas = $inditas.AddDays(1)
                }
            }
            $inditas = ($inditas.Date).AddHours($Tomorrow)
        }
        
        if($Seconds -or $Minutes)
        {
            for($i = $vissza; $i -ge 0; $i--)
            {
                $ts = [TimeSpan]::FromSeconds($i)
                $hatravan = $ts.ToString("mm':'ss")
                Clear-Line
                Write-Host "`rAz újrapróbálkozásig még $hatravan" -NoNewline
                Start-Sleep -Seconds 1
            }
        }
        elseif($Hours)
        {
            for($i = $vissza; $i -ge 0; $i--)
            {
                $ts = [TimeSpan]::FromSeconds($i)
                $hatravan = $ts.ToString("hh':'mm':'ss")
                Clear-Line
                Write-Host "`rAz újrapróbálkozásig még $hatravan" -NoNewline
                Start-Sleep -Seconds 1
            }
        }
        else
        {
            $ido = $inditas - $most
            for($i = $ido.TotalSeconds; $i -ge 0; $i--)
            {
                $ts = [timespan]::FromSeconds($i)
                $hatravan = $ts.ToString("d' nap, 'hh':'mm':'ss")
                
                Write-Host "`rA folyamat megkezdéséig még hátravan $hatravan" -NoNewline
                Start-Sleep -s 1
            }
        }
    }
    else
    {
        Write-Host "A megengedettnél több, vagy kevesebb érvényes bemenetet adtál meg!" -ForegroundColor Red
    }
}

##### FRISSÍTVE #####
function Get-Valasztas
{
    ###############################################################
    #
    # Leírás:       Felhasználi bevitel helyességét ellenőrző függvény. Csak akkor enged továbblépni
    #               ha a felhasználó a megadott értékek egyikét adja meg. A függvény használható Igen-Nem típusú
    #               eldöntendő kérdések bekérésére is.
    #               Ha van bemenetként Engedélyezett tömb, úgy a YesNo kapcsoló figyelmen kívül hagyásra kerül.
    #               
    # Bemenet:      -Engedelyezettek:   az engedélyezett lehetőségek tömbje, megadása nélkül press-key-to continue módon működik a függvény
    #               -Idokorlat:         kapcsoló, ha szeretnénk, hogy egy idő után magától kiválasztódjon az első választás
    #               -YesNo:             kapcsoló, kiválasztásával a függvény automatikusan Igen-Nem döntésre áll át
    #
    # Kimenet:      valasztas:          Ellenőrzött, az előzetesen megadott feltételeknek megfelelő karakter
    #
    # Függőségek:   Nincs
    #
    # Hiba:         A $host.UI.RawUI.KeyAvailable működési elve miatt, ha már volt korábban billentyűleütés
    #               a jelenlegi futás során, az -Idokorlat kapcsoló nem használható. Ha volt korábban leütés,
    #               a $host.UI.RawUI.KeyAvailable ezt érzékeli, viszont a tényleges billentyű tartalmat
    #               már nem lehet lekérni. Ilyen esetben a kapcsoló használata hibát nem eredményez,
    #               a függvény egyszerűen csak úgy viselkedik, mintha ki lenne kapcsolva.
    #
    ###############################################################

    param(
        [Parameter(Mandatory=$false)]$Engedelyezettek,
        [Switch]$Idokorlat,
        [Switch]$YesNo
        )

    if($YesNo -and !$Engedelyezettek)
    {
        Write-Host "(I) Ha igen`n(N) Ha nem"
        $Engedelyezettek = @("I", "N")
    }
    else
    {
        $YesNo = $False
    }

    if(!$Engedelyezettek)
    {
        $valasztas = ($host.UI.RawUI.ReadKey()).Character
    }
    else
    {
        do
        {
            if($probalkozottmar)
            {
                Write-Host "`n`nKérlek, csak a megadott lehetőségek közül válassz!" -ForegroundColor Yellow
            }

            $loopcount = $Script:config.varakozasbevitelre * 100
            do
            {
                if($Idokorlat -and !$host.UI.RawUI.KeyAvailable)
                {
                    Start-Sleep -Milliseconds 10
                    if($loopcount -eq 0)
                    {
                        $valasztas = $Engedelyezettek[0]
                    }
                    $loopcount--

                    $masodperc = [Math]::Round($loopcount/100)

                    Write-Host "`rVálassz ($masodperc másodperc múlva az első menüpont kerül kiválasztásra): " -NoNewLine
                }
                else
                {
                    Write-Host "`rVálassz: " -NoNewLine
                }

                if($host.UI.RawUI.KeyAvailable)
                {
                    [string]$valasztas = ($host.UI.RawUI.ReadKey()).Character
                }
            } while (!$valasztas)

            $endloop = $False
            foreach($engedelyezett in $Engedelyezettek)
            {
                if ($valasztas -eq $engedelyezett)
                {
                    $endloop = $True
                    Break
                }
            }
            $probalkozottmar = $True
        } while (!$endloop)
        Write-Host
    }

    if($YesNo)
    {
        if($valasztas -eq "I")
        {
            [bool]$valasztas = $True
        }
        else
        {
            [bool]$valasztas = $False
        }
    }

    return $valasztas
}

##### FRISSÍTVE #####
function Show-JobInProgress
{
    ###############################################################
    #
    # Leírás:       Indikátor az elindított job-ok futásának jelzésére. A függvény kap egy job-ot,
    #               és a megjelenítendő szöveget, majd addig jelzi a felhasználónak a futást,
    #               amíg a job véget nem ér.
    #               
    # Bemenet:      -Text:      a job futása alatt megjelenítendő szöveg, kötelező megadni
    #               -Job:       maga a job, aminek a futását jelezni akarjuk, kötelező megadni
    #
    # Kimenet:      a job eredménye, akármi legyen is az
    #
    # Függőségek:   * Clear-Line
    #
    ###############################################################

    param(
        [Parameter(Mandatory=$true)]$Text,
        [Parameter(Mandatory=$true)]$Job
        )

    $speed = 300
    do
    {
        Write-Host "`r$Text." -NoNewLine
        Start-Sleep -milliseconds $speed
        if($Job.State -ne "Running")
        {
            Break
        }
        Clear-Line
        Write-Host "`r$Text.." -NoNewLine
        Start-Sleep -milliseconds $speed
        if($Job.State -ne "Running")
        {
            Break
        }
        Clear-Line
        Write-Host "`r$Text..." -NoNewLine
        Start-Sleep -milliseconds $speed
        if($Job.State -ne "Running")
        {
            Break
        }
        Clear-Line
    } while ($Job.State -eq "Running")
    Write-Host
    $return = $Job | Receive-Job

    return $return
}

##   Lekérő függvények   ##
#  Függvények információ  #
##      lekérésére       ##
###########################

function Get-UtolsoUser
{
    ###############################################################
    #
    # Leírás:       Utoló bejelentkezett user nevét lekérő függvény. Működik úgy nagyjából.
    #               
    # Bemenet:      -Gepnev:     A lekérdezni kívánt gép neve, kötelező megadni
    #
    # Kimenet:      Az utolsó bejelentkezett felhasználó neve, vagy ha valami hiba történt menet közben, hibaüzenet
    #
    # Függőségek:   AD modul megléte
    #
    ###############################################################

    param ([Parameter(Mandatory=$True)]$Gepnev)
    
    try
    {
        $utolsouserfull = (Get-WmiObject -Class win32_computersystem -ComputerName $Gepnev).Username # Bekérjük a user felhasználónevét
        $utolsouser = $utolsouserfull.Split("\") # A név STN\bejelenkezési név formátumban jön. Ezt szétbontjuk, hogy megkapjuk a bejelentkezési nevet
        $user = Get-ADUser $utolsouser[1] # A bejelentkezési névvel lekérjük a felhasználó adatait
        return $user.Name # A felhasználó megjelenő nevét adjuk vissza eredményként
    }
    
    catch [System.Runtime.InteropServices.COMException]
    {
        return "Felhasználónév lekérése megtagadva!"
    }

    catch
    {
        return "Nincs bejelentkezett felhasználó"
    }
}

###################################################################################################
###                          A SCRIPT SAJÁT OSZTÁLYAI ÉS FÜGGVÉNYEI                             ###
###################################################################################################

#-#-#-#-#-#-#-#-#-#-#-#-#-#-#-#-#-#-#-#-#-#-#-#-#-#-#-#-#-#-#-#-#-#-#-#-#-#-#-#-#-#-#-#-#-#-#-#-#-#
#-#-#                                     OSZTÁLYOK                                           #-#-#
#-#-#-#-#-#-#-#-#-#-#-#-#-#-#-#-#-#-#-#-#-#-#-#-#-#-#-#-#-#-#-#-#-#-#-#-#-#-#-#-#-#-#-#-#-#-#-#-#-#

#####
##  Objektumok
#####

Class CSV
{
    $Nev
    $kimenet

    CSV($nevelotag, $kozeptag)
    {
        $this.Nev = "$($nevelotag)-$kozeptag.csv"
        $this.kimenet = "$($Script:config.csvkonyvtar)\VÉGEREDMÉNY_$($this.Nev)"
    }

    Sync($eszkoz, $id)
    {
        # Az eredményt CSV-be író metódus. Először ellenőrzi, hogy létezik-e a fájl, és létrehozza, ha nem.
        # Aztán ellenőrzi, hogy benne van-e az adott menteni kívánt elem, ha nem, beleírja.
        # Végül, ha az elem már benne volt, felülírja azt az újjal.
        if(!(Test-Path $this.kimenet))
        {
            $eszkoz | Export-Csv -encoding UTF8 -path $this.kimenet -NoTypeInformation -Append -Force -Delimiter ";"
        }
        elseif(!(Select-String -Path $this.kimenet -Pattern $eszkoz.$id))
        {
            $eszkoz | Export-Csv -encoding UTF8 -path $this.kimenet -NoTypeInformation -Append -Force -Delimiter ";"
        }
        else
        {
            $csvdata = Import-Csv -Path $this.kimenet -Delimiter ";"

            $update = New-Object System.Collections.ArrayList($null)
            foreach ($sor in $csvdata)
            {
                if($sor.$id -ne $eszkoz.$id)
                {
                    [Void]$update.Add($sor)
                }
            }
            [Void]$update.Add($eszkoz)
            $update | Export-Csv -encoding UTF8 -path $this.kimenet -NoTypeInformation -Force -Delimiter ";"
        }
    }
}

Class Eszkoz
{
    $Eszkoznev
    $IPaddress
    $MACaddress
    $SwitchNev
    $SwitchIP
    $Port
    $Felhasznalo
    $Megjegyzes
    hidden $Tablanev
    hidden $Finished
    hidden $DBid
    hidden $DBidValue
    hidden $Local
    hidden $Remote
    hidden $Lekerdezes
    hidden $Sorok

    Eszkoz()
    {
        $this.Finished = $False
    }

    Eszkoz($bemenet)
    {
        if([IPcim]::CheckPattern($bemenet))
        {
            $this.IPaddress = $bemenet
        }
        else
        {
            $this.Eszkoznev = $bemenet
        }
    }

    Eszkoz($IP, $eszkoznev)
    {
        $this.IPaddress = $IP
        $this.Eszkoznev = $eszkoznev
    }

    Eszkoz($Eszkoznev, $IPaddress, $MACaddress, $SwitchNev, $SwitchIP, $Port, $Felhasznalo, $Megjegyzes)
    {
        $this.Eszkoznev = $Eszkoznev
        $this.IPaddress = $IPaddress
        $this.MACaddress = $MACaddress
        $this.SwitchNev = $SwitchNev
        $this.SwitchIP = $SwitchIP
        $this.Port = $Port
        $this.Felhasznalo = $Felhasznalo
        $this.Megjegyzes = $Megjegyzes
    }

    SetNev()
    {
        try
        {
            $namesplit = ([System.Net.DNS]::GetHostEntry($this.IPaddress).HostName)
            $kimenet = $namesplit.Split(".")
            $this.Eszkoznev = $kimenet[0]
        }
        catch [System.Net.Sockets.SocketException]
        {
            $this.Eszkoznev = "Nem elérhető"
        }
    }

    SetIP($IP)
    {
        $this.IPaddress = $IP
    }

    SetMAC($MAC)
    {
        $this.MACaddress = $MAC
    }

    SetSwitchnev($switchnev)
    {
        $this.SwitchNev = $switchnev
    }

    SetSwitchIP($switchIP)
    {
        try
        {
            $this.SwitchIP = $switchIP.Trim("(", ")", "[", "]", ".")
        }
        catch
        {
            Show-Debug $switchIP
            Show-Debug $error[0]
            $this.SwitchIP = "IP cím nem elérhető"
        }
    }

    SetPort($port)
    {
        $this.Port = $port
    }

    SetFelhasznalo()
    {
        if($script:runtime.admin)
        {
            $this.Felhasznalo = Get-UtolsoUser $this.Eszkoznev
        }
    }

#### ADATBÁZIS METÓDUSOK ####
    SetTableName($ounev)
    {
        $this.Tablanev = [SQL]::SetTableName("Eszkoz", $ounev)
    }

    SetDBid()
    {
        if($this.Eszkoznev)
        {
            $this.DBid = "Eszkoznev"
            $this.DBidValue = $this.Eszkoznev
        }
        elseif($this.MACaddress)
        {
            $this.DBid = "MACaddress"
            $this.DBidValue = $this.MACaddress
        }
        elseif($this.IPaddress)
        {
            $this.DBid = "IPaddress"
            $this.DBidValue = $this.IPaddress
        }
    }

    CreateTable($ounev)
    {
        $this.SetTableName($ounev)
        $attribhash = @{
            Eszkoznev = "varchar(255)"
            IPaddress = "varchar(255)"
            MACaddress = "varchar(255)"
            SwitchNev = "varchar(255)"
            SwitchIP = "varchar(255)"
            Port = "varchar(255)"
            Felhasznalo = "varchar(255)"
            Finished = "varchar(255)"
            Megjegyzes = "varchar(255)"
          }                     
        $script:runtime.sql.CreateTable($this.Tablanev, $attribhash)
    }

    AddRecord()
    {
        $commandtext = "INSERT INTO $($this.Tablanev) (Eszkoznev, IPaddress, MACaddress, SwitchNev, SwitchIP, Port, Felhasznalo, Finished, Megjegyzes) Values (@Eszkoznev, @IPaddress, @MACaddress, @SwitchNev, @SwitchIP, @Port, @Felhasznalo, @Finished, @Megjegyzes)"
        $attribnames = @("@Eszkoznev", "@IPaddress", "@MACaddress", "@SwitchNev", "@SwitchIP", "@Port", "@Felhasznalo", "@Finished", "@Megjegyzes")
        $values = @($this.Eszkoznev, $this.IPaddress, $this.MACaddress, $this.SwitchNev, $this.SwitchIP, $this.Port, $this.Felhasznalo, $this.Finished, $this.Megjegyzes)

        $script:runtime.sql.AddRecord($commandtext, $attribnames, $values)
    }

    UpdateValue($attrib, $value)
    {
        if(!$this.DBidValue)
        {
            $this.SetDBid()
        }
        if($this.DBidValue)
        {
            $commandtext = "UPDATE $($this.Tablanev) SET $attrib = '$value' WHERE $($this.DBid) LIKE '$($this.DBidValue)'"
            Show-Debug $commandtext
            $script:runtime.sql.UpdateDatabase($commandtext)
        }
        else
        {
            Out-Result -Text "Az objektumnak nincs olyan egyedi azonosítója, ami használható az adatbázis rekord frissítésére!" -Level "err" -Tag "err"
        }
    }

    UpdateRecord()
    {
        $this.UpdateValue("Eszkoznev", $this.Eszkoznev)
        $this.UpdateValue("IPaddress", $this.IPaddress)
        $this.UpdateValue("MACaddress", $this.MACaddress)
        $this.UpdateValue("SwitchNev", $this.SwitchNev)
        $this.UpdateValue("SwitchIP", $this.SwitchIP)
        $this.UpdateValue("Port", $this.Port)
        $this.UpdateValue("Felhasznalo", $this.Felhasznalo)
        $this.UpdateValue("Finished", $this.Finished)
        $this.UpdateValue("Megjegyzes", $this.Megjegyzes)
    }

    DeleteRecord($attrib, $value)
    {
        $commandtext = "DELETE FROM $($this.tablanev) WHERE $attrib LIKE '$value'"
        $script:runtime.sql.QueryTable($commandtext)
    }

#### SWITCH LEKÉRDEZÉS METÓDUSOK ####
    Lekerdez($keresesiparancs, $local, $remote, $allapot)
    {
        $this.Local = $local
        $this.Remote = $remote
        $failcount = 0
        $pinglocal = "ping $($local.IPaddress)"
        $pingremote = "ping $($remote.IPaddress)"
        $this.Lekerdezes = $false
        $this.IPaddress = $remote.IPaddress
        $this.MACaddress = $remote.MACaddress
        if(!$this.Eszkoznev)
        {
            if($remote.Eszkoznev)
            {
                $this.Eszkoznev = $Remote.Eszkoznev
            }
            else
            {
                $this.SetNev()
            }
        }
        $result = $null
        [String[]]$parancs = @($pinglocal, $pingremote, $keresesiparancs)
        $waittimeorig = $script:config.waittime
        do
        {
            Out-Result "$allapot A(z) $($this.IPaddress) IP című eszköz helyének lekérdezése folyamatban..." -Overwrite
            $result = [Telnet]::InvokeCommands($parancs)
            Show-Debug $result
            if(!$result)
            {
                Out-Result -Text "A(z) $($this.IPaddress) című eszköz lekérdezése során a programnak nem sikerült csatlakozni a(z) $($script:config.switch) IP című switchhez!" -Tag "conerr" -Level "err"
            }
            elseif ($result | Select-String -Pattern "trace completed")
            {
                $This.Lekerdezes = $True
                Show-Debug "Az útvonal lekérése sikeres"
            }
            if ($result | Select-String -Pattern "trace aborted")
            {
                Show-Debug "Az útvonal lekérése sikertelen, nem próbálkozom újra"
                $failcount = $script:config.maxhiba
            }
            elseif (!$this.Lekerdezes -and $failcount -lt $script:config.maxhiba)
            {
                Show-Debug "Az útvonal lekérése sikertelen, újrapróbálkozom hosszabb idővel, ami jelenleg: $($script:config.waittime) ezredmásodperc"
                $failcount++
                $visszamaradt = $script:config.maxhiba - $failcount
                Write-Host "$allapot " -NoNewline
                Out-Result -Text "A(z) $($this.IPaddress) eszköz helyének lekérdezése most nem járt sikerrel. Még $visszamaradt alkalommal újrapróbálkozom!" -Level "warn" -Tag "timeout"
                if ($failcount -eq $script:config.maxhiba)
                {
                    Write-Host "$allapot " -NoNewline
                    Out-Result -Text "A(z) $($this.IPaddress) eszköz helyének lekérdezése a(z) $($script:config.switch) IP című switchről időtúllépés miatt nem sikerült" -Tag "timeout" -Level "err"
                    Show-Debug $this.result
                }
                $script:config.waittime = $script:config.waittime + 1000
            }
        }while (!$this.Lekerdezes -and $failcount -lt $script:config.maxhiba)
        $script:config.waittime = $waittimeorig
        if($this.Lekerdezes)
        {
            $this.Feldolgoz($result)
        }
        else
        {
            $this.Hibakeres($result)
        }
    }

    Feldolgoz($result)
    {
        $eszkozhely = 0
        $sajateszkoz = 0
        $this.Sorok = $result.Split("`r`n")
        for ($i = 0; $i -lt $this.Sorok.Length; $i++)
        {
            if ($this.Sorok[$i] | Select-String -pattern "=>")
            {
                if ($sajateszkoz -eq 0)
                {
                    $sajateszkoz = $i
                }
                $eszkozhely = $i
            }
        }
        
        $utolsosor = $this.Sorok[$eszkozhely].Split(" ")
        $this.SwitchNev = $utolsosor[1]
        $this.SwitchIP = $utolsosor[2]
        $this.Port = $utolsosor[6]
        if(!$this.Local.Kesz())
        {
            $elsosor = $this.Sorok[$sajateszkoz].Split(" ")
            $this.Local.SwitchNev = $elsosor[1]
            $this.Local.SwitchIP = $elsosor[2]
            $this.Local.Port = $elsosor[4]
        }
        $this.Log()
    }

    Hibakeres($result)
    {
        Show-Debug "Eredmény hibakeresés"
        Show-Debug $result
        $this.Local.Megbizhato = $false
        if($result | Select-String -Pattern "Unable to locate port for")
        {
            Show-Debug "Unable to locate port hiba"
            $this.Sorok = $result.Split("`r`n")
            foreach ($sor in $this.Sorok)
            {
                if ($sor | Select-String -Pattern "Unable to locate port for")
                {
                    Show-Debug "Az eszköz megtalálva"
                    $eredmeny = $sor.Split(" ")
                    $this.SwitchNev = $eredmeny[8]
                    $this.SwitchIP = $eredmeny[9]
                    $this.Megjegyzes = "Az eszköz valószínűleg egy nem Catalyst switchez kapcsolódik fizikálisan (HP, vagy Cisco SF széria)"
                    Out-Result -Text "A(z) $($this.Remote.IPaddress) eszköz helye a $($this.SwitchNev) ($($this.SwitchIP)) switchig követhető vissza, a pontos port lekérése hibába ütközött" -Tag "routeerr" -Level "warn"
                    Break
                }
            }
        }
    
        elseif ($result | Select-String -Pattern "Success rate is 0 percent")
        {
            if($this.Remote.Allapot() -and $this.Local.Allapot())
            {
                $this.Megjegyzes = "Az eszköz online, de a switchről valamiért nem érhető el"
                Out-Result -Text $this.Megjegyzes -Tag "unreachable" -Level "err"
            }
            else
            {
                Out-Result -Text "A lekérdezni kívánt, vagy a kiinduló gép nem volt elérhető" -Tag "unreachable" -Level "err"
            }
        }
        elseif($result | Select-String -Pattern "Mac address not found")
        {
            Out-Result -Text "A(z) $($this.Remote.IPaddress) eszköz ARP tábla hiba miatt nem lekérdezhető" -Level "err" -Tag "arperr"
        }
        else
        {
            Add-Log -Text $result -Tag "err"
        }
    }

    Log()
    {
        Add-Log -Text "A(z) $($this.remote.IPaddress) IP című eszköz a(z) $($this.switchnev) $($this.switchip) switch $($this.eszkozport) portján található." -Tag "success"
    }

    [bool]Siker()
    {
        return $this.Lekerdezes
    }
}

Class Local
{
    $Gepnev
    $IPaddress
    $MACaddress
    $Mask
    $SwitchNev
    $SwitchIP
    $Port
    $Megbizhato

    Local()
    {
        $this.Gepnev = HOSTNAME.EXE
        $gateway = (Get-NetRoute -DestinationPrefix "0.0.0.0/0").NextHop
        $getMAC = get-wmiobject -class "win32_networkadapterconfiguration" | Where-Object {$_.DefaultIPGateway -Match $gateway}
        $this.FinalizeConstruct($getMAC)
        $This.Mask = (Get-NetIPAddress | Where-Object {$_.IPAddress -match $this.IPAddress -and $_.AddressFamily -match "IPv4"} ).PrefixLength
    }

    Local($remotegepnev)
    {
        $this.Gepnev = $remotegepnev
        $this.Megbizhato = $true
        try
        {
            $job = Invoke-Command -ComputerName $this.Gepnev -ScriptBlock { (Get-NetRoute -DestinationPrefix "0.0.0.0/0").NextHop } -AsJob -JobName "Gateway"
            $job | Wait-Job -Timeout 20 > $null
            $gateway = $job | Receive-Job
            
            if($gateway)
            {
                $getMAC = get-wmiobject -class "win32_networkadapterconfiguration" -ComputerName $this.Gepnev | Where-Object {$_.DefaultIPGateway -Match $gateway}
                $this.FinalizeConstruct($getMAC)
            }
            else
            {
                $message = "A(z) $($this.Gepnev) számítógép MACAddressének lekérése időtúllépés miatt sikertelen"
                Add-Log -Text $message -Tag "timeout"
                Write-Host "$message!" -ForegroundColor Red
            }
        }
        catch [System.Management.Automation.Remoting.PSRemotingTransportException]
        {
            $message = "$($this.Gepnev) Időeltérés a helyi és távoli számítógép között"
            Add-Log -Text $message -Tag "autherr"
            Write-Host "$message! Az eszköz MAC addresse nem kérhető le!" -ForegroundColor Red
        }
        catch
        {
            $message = "$($this.Gepnev) $($_.Exception.GetType().Fullname) $($error[0])"
            Write-Host $message -ForegroundColor Red
            Add-Log -Text $message -Tag "err"
        }
    }

    FinalizeConstruct($getMAC)
    {
        try
        {
            $kimenet = ($getMAC.MACAddress).Split(":")
            $this.MACaddress = "$($kimenet[0])$($kimenet[1]).$($kimenet[2])$($kimenet[3]).$($kimenet[4])$($kimenet[5])"
            $this.IPaddress = (($getMAC.IPAddress).Split(","))[0]
        }
        catch
        {

        }
    }

    [bool]Kesz()
    {
        if(!$this.SwitchNev)
        {
            return $false
        }
        else
        {
            return $true
        }
    }

    [bool]Allapot()
    {
        if(Test-Connection $this.SwitchIP -Quiet -Count 1)
        {
            Return $True

        }
        else
        {
            Return $False
        }
    }
}

Class Remote
{
    [string]$Eszkoznev
    [string]$IPaddress
    [string]$MACaddress
    $Online
    hidden $EszkozID

    Remote()
    {
        $this.AdatBeker()
    }

    Remote($keresetteszkoz)
    {
        $this.EszkozID = $keresetteszkoz
        $this.AdatKitolt()
    }

    AdatBeker()
    {
        $this.EszkozID= Read-Host -Prompt "Keresett eszköz IP címe, vagy neve"
        $this.AdatKitolt()
    }

    AdatKitolt()
    {
        if([IPcim]::CheckPattern($this.EszkozID))
        {
            $this.IPaddress = $this.EszkozID
        }
        else
        {
            $this.Eszkoznev = $this.EszkozID
            try
            {
                $this.GetIP($this.EszkozID)
            }
            catch { }
        }
        $this.Allapot()
    }

    GetMAC()
    {
        if(!$this.GetMACfromARP())
        {
            $this.GetMACfromAD()
        }
    }

    [Bool]GetMACfromARP()
    {
        ping $this.IPaddress -n 1 | Out-Null
        $getRemoteMAC = arp -a | ConvertFrom-String | Where-Object { $_.P2 -eq $this.IPaddress }
        try
        {
            Show-Debug $getRemoteMAC
            $kimenet = ($getRemoteMAC.P3).Split("-")
            $this.MACaddress = "$($kimenet[0])$($kimenet[1]).$($kimenet[2])$($kimenet[3]).$($kimenet[4])$($kimenet[5])"
            Show-Debug $this.MACaddress
            return $true
        }
        catch
        {
            Show-Debug "GetMACfromARP hiba"
            return $false
        }
    }

    GetMACfromAD()
    {
        try
        {
            $job = Invoke-Command -ComputerName $this.Eszkoznev -ScriptBlock { (Get-NetRoute -DestinationPrefix "0.0.0.0/0").NextHop } -AsJob -JobName "Gateway"
            $gateway = Show-JobInProgress -Job $job -Text "Kísérlet a(z) $($this.Eszkoznev) számítógép MACAddressének lekérésére"
            $gateway = $job | Receive-Job
            
            if($gateway -and ($gateway -match "Exception"))
            {
                $getMAC = get-wmiobject -class "win32_networkadapterconfiguration" -ComputerName $this.Eszkoznev | Where-Object {$_.DefaultIPGateway -Match $gateway}
                $kimenet = ($getMAC.MACAddress).Split(":")
                $this.MACaddress = "$($kimenet[0])$($kimenet[1]).$($kimenet[2])$($kimenet[3]).$($kimenet[4])$($kimenet[5])"
            }
            else
            {
                Out-Result -Text "A(z) $($this.Eszkoznev) számítógép MACAddressének lekérése sikertelen" -Tag "timeout" -Overwrite -Level "err"
            }
        }
        catch [System.Management.Automation.Remoting.PSRemotingTransportException]
        {
            Out-Result -Text "$($this.Eszkoznev) Időeltérés a helyi és távoli számítógép között" -Tag "autherr" -Overwrite -Level "err"
        }
        catch
        {
            Out-Result -Text "$($this.Eszkoznev) $($_.Exception.GetType().Fullname) $($error[0])" -Level "err" -Tag "err" -Overwrite
        }
    }

    [bool]Allapot()
    {
        $this.Online = (Test-Connection $this.EszkozID -Quiet -Count 1)
        if(!$this.Online)
        {
            Out-Result -Text "A(z) $($this.EszkozID) eszköz jelenleg nem elérhető" -Tag "down" -Level "warn" -Overwrite
        }
        return $this.Online
    }

    GetIP($hostname)
    {
        $addresses = [System.Net.Dns]::GetHostAddresses($hostname)
        foreach ($address in $addresses)
        {
            if([IPcim]::CheckPattern($address))
            {
                $this.IPaddress = $address
                Break
            }
        }
    }

    [bool]Elerheto()
    {
        return $this.Online
    }

    [string]EszkozAllapot()
    {
        if($this.Online)
        {
            return "Online"
        }
        else
        {
            return "Offline"
        }
    }
}

Class PingDevice
{
    $IPcím
    $EszközNév = $null
    $Állapot

    PingDevice($eszkoz)
    {
        if([IPcim]::CheckPattern($eszkoz))
        {
            $this.IPcím = $eszkoz
        }
        else
        {
            $this.EszközNév = $eszkoz
        }
    }

    [Bool]Online($eszkoz)
    {
        $online = $false
        switch ($script:config.method)
        {
            1 { $online = Test-Ping $eszkoz }
            2 { $online = (Test-Connection $eszkoz -Quiet -Count 1) }
            Default{ $online = Test-Ping $eszkoz }
        }
        if($online)
        {
            $this.Állapot = "Online"
        }
        else
        {
            $this.Állapot = "Offline"
        }

        return $online
    }

    NameByIP()
    {
        if ($script:config.nevgyujtes)
        {
            try
            {
                $namesplit = ([System.Net.DNS]::GetHostEntry($this.IPcím)).HostName
                $kimenet = $namesplit.Split(".")
                $this.EszközNév = $kimenet[0]
            }
            catch [System.Net.Sockets.SocketException]
            {
                $this.EszközNév = "Nem elérhető"
            }
        }
    }

    IpByName()
    {
        $addresses = [System.Net.Dns]::GetHostAddresses($this.EszközNév)
        foreach ($address in $addresses)
        {
            if ([IPcim]::CheckPattern($address))
            {
                $this.IPcím = $address
                Break
            }
        }
    }

    [String]Nevkiir()
    {
        if($this.EszközNév)
        {
            $neve = "; Neve: $($this.EszközNév)"
        }
        else
        {
            $neve = ""
        }

        return $neve
    }

    OutCSV($csvkimenet)
    {
        if(($script:config.logonline) -and ($script:config.logoffline))
        {
            $this | export-csv -encoding UTF8 -path $csvkimenet -NoTypeInformation -Append -Force -Delimiter ";"
        }
        elseif(($script:config.logonline) -and $this.Állapot)
        {
            $this | export-csv -encoding UTF8 -path $csvkimenet -NoTypeInformation -Append -Force -Delimiter ";"
        }
        elseif(($script:config.logoffline) -and !$this.Állapot)
        {
            $this | export-csv -encoding UTF8 -path $csvkimenet -NoTypeInformation -Append -Force -Delimiter ";"
        }
    }
}

Class SwitchDev
{
    $IPaddress
    $Eszkoznev
    $Online
    $Kesz

    SwitchDev()
    {

    }

    SwitchDev($IPaddress, $Eszkoznev)
    {
        $this.IPaddress = $IPaddress
        $this.Eszkoznev = $Eszkoznev
        $this.Online = $true
        $this.Kesz = $false
    }
}

# Tiszta
Class IPcim
{
    $tag1
    $tag2
    $tag3
    $tag4

    IPcim($bemenet)
    {
        do
        {
            if([IPcim]::CheckPattern($bemenet))
            {
                $this.Set($bemenet)
            }
            else
            {
                Write-Host "Nem érvényes IP címet adtál meg! Próbálkozz újra!" -ForegroundColor Red
                $bemenet = Read-Host -Prompt "IP cím"
            }
        }while (!([IPcim]::CheckPattern($bemenet)))
    }

    Set($bemenet)
    {
        $kimenet = $bemenet.Split(".")
        [int32]$this.tag1 = $kimenet[0]
        [int32]$this.tag2 = $kimenet[1]
        [int32]$this.tag3 = $kimenet[2]
        [int32]$this.tag4 = $kimenet[3]
    }

    Static [Bool]CheckPattern($inputtocheck)
    {
        $pattern = "^([1-9]|[1-9][0-9]|1[0-9][0-9]|2[0-4][0-9]|25[0-5])(\.([0-9]|[1-9][0-9]|1[0-9][0-9]|2[0-4][0-9]|25[0-5])){3}$"
        if($inputtocheck -match $pattern)
        {
            Return $True
        }
        else
        {
            Return $False
        }
    }

    [string]ToString()
    {
        return "$($this.tag1).$($this.tag2).$($this.tag3).$($this.tag4)"
    }

    Add($number)
    {
        $maradek1 = $number - (256 - $this.tag4)
        if($maradek1 -lt 0)
        {
            $this.tag4 = $this.tag4 + $number
        }
        else
        {
            $this.tag4 = 0 + ($maradek1 % 256)
            $maradek2 = [Math]::truncate($maradek1 / 256)
            if(($maradek2 - (255 - $this.tag3)) -lt 0)
            {
                $this.tag3 = $this.tag3 + $maradek2 + 1
            }
            else
            {
                $this.tag3 = 0 + ($maradek2 % 256)
                $maradek3 = [Math]::truncate($maradek2 / 256)
                if(($maradek3 - (255 - $this.tag2)) -lt 0)
                {
                    $this.tag2 = $this.tag2 + $maradek3 + 1
                }
                else
                {
                    $maradek4 = [Math]::truncate($maradek3 / 256)
                    $this.tag1 = $this.tag1 + $maradek4 + 1
                    $this.tag2 = 0 + ($maradek3 % 256)
                }
            }
        }
    }

    [Bool]BiggerThan($IP2)
    {     
        $elsonagyobb = $false
        if ($this.Tag1 -gt $IP2.Tag1)
        {
            $elsonagyobb = $true
        }
        elseif($this.Tag1 -eq $IP2.Tag1)
        {
            if($this.Tag2 -gt $IP2.Tag2)
            {
                $elsonagyobb = $true
            }
            elseif($this.Tag2 -eq $IP2.Tag2)
            {
                if($this.Tag3 -gt $IP2.Tag3)
                {
                    $elsonagyobb = $true
                }
                elseif($this.Tag3 -eq $IP2.Tag3)
                {
                    if($this.Tag4 -gt $IP2.Tag4)
                    {
                        $elsonagyobb = $true
                    }
                }
            }
        }
    
        return $elsonagyobb 
    }

    [Int]Count($utolsoIP)
    {       
        $elsotag = $utolsoIP.tag1 - $this.tag1 + 1
        $masodiktag = (256 - $this.tag2) + ($utolsoIP.tag2+1) + ((($elsotag - 2) * 256))
        $harmadiktag = (256 - $this.tag3) + ($utolsoIP.tag3+1) + ((($masodiktag - 2) * 256))
        $negyediktag = (256 - $this.tag4) + ($utolsoIP.tag4+1) + ((($harmadiktag - 2) * 256))

        return $negyediktag
    }

    [Object]Range($zaroIP)
    {
        $eszkoz = New-Object System.Collections.ArrayList($null)
        $zaroIP = $zaroIP.ToString()
        $eszkoz.Add($this.ToString()) > $null
        do
        {
            $this.Add(1)
            $eszkoz.Add($this.ToString()) > $null
        } while ($this.ToString() -ne $zaroIP)

        return $eszkoz
    }

    [Object]RangeKihagyassal($zaroIP, $elsokihagyott, $utolsokihagyott)
    {
        $eszkoz = New-Object System.Collections.ArrayList($null)
        $eszkoz.Add($this.ToString()) > $null
        $kihagyas = $elsokihagyott.Count($utolsokihagyott)
        $zaroIP = $zaroIP.ToString()
        $elsokihagyott = $elsokihagyott.ToString()
        do
        {
            $this.Add(1)
            if ($this.ToString() -eq $elsokihagyott)
            {
                $this.Add($kihagyas)
            }
            $eszkoz.Add($this.ToString()) > $null
        } while ($this.ToString() -ne $zaroIP)

        return $eszkoz
    }
}

Class MasVLAN
{
    $subnet
    $mask
    $tracegep

    MasVLAN($tracegep)
    {
        $this.tracegep = $tracegep
        $this.mask = $tracegep.Mask
        $vlan = ($tracegep.IPAddress).Split(".")
        $this.subnet = "$($vlan[0]).$($vlan[1]).$($vlan[2])"
    }
}

#####
##  Végrehajtó osztályok.
#####

Class Telnet
{
    Static $Felhasznalonev = $null
    Static $Jelszo = $null
    Static $nonroot

    Static Login()
    {
        if (![Telnet]::Felhasznalonev -or ![Telnet]::Jelszo)
        {
            $login = $false
            do
            {
                #[Telnet]::SetSwitch()
                Show-Cimsor "Bejelentkezés a $($script:config.switch) switchre"
                [Telnet]::LoginCreds()
                $login = [Telnet]::TestConnection()

                if (!$login)
                {
                    Write-Host "Újrapróbálkozol a switch bejelentkezési adatainak megadásával?" -ForegroundColor Red
                    $valassz = Get-Valasztas -YesNo
                    if($valassz -ne "I")
                    {
                        Exit
                    }
                }
            }while(!$login)
        }
    }

    Static SetConnection($switch, $felhasznalonev, $jelszo)
    {
        $script:config.switch = $switch
        [Telnet]::felhasznalonev = $felhasznalonev
        [Telnet]::jelszo = $jelszo
    }

    Static LoginCreds()
    {
        [Telnet]::felhasznalonev = Read-Host -Prompt "Felhasználónév"
        $pass = Read-Host -AsSecureString -Prompt "Jelszó"
        [Telnet]::jelszo = [System.Runtime.InteropServices.Marshal]::PtrToStringAuto([System.Runtime.InteropServices.Marshal]::SecureStringToBSTR($pass))
    }

    Static SetSwitch()
    {
        Show-Cimsor "Switch bejelentkezés"
        Write-Host "Az alapértelmezett switchet használod ($($script:config.switch)), vagy megadod kézzel a címet?`nAdd meg a switch IP címét, ha választani szeretnél, vagy üss Entert, ha az alapértelmezettet használnád!"
        do
        {
            $kilep = $true
            $valassz = Read-Host "A switch IP címe"
            if ($valassz)
            {
                if (!(Test-Connection $valassz -Quiet -Count 1))
                {
                    Out-Result -Text "A(z) $valassz IP címen nem található eszköz" -Tag "unreachable" -NoNewLine -Level "err"
                    Out-Result -Text ", add meg újra a címet, vagy üss Entert az alapértelmezett switch használatához!" -Level "err"
                    $kilep = $false
                }
                if($kilep)
                {
                    $script:config.switch = $valassz
                }
            }
        }while(!$kilep)
    }

    Static SetSwitch($switchIP)
    {
        $Script:config.switch = $switchIP
    }

    Static [bool]TestConnection()
    {
        $login = $false
        Write-Host "`nKísérlet csatlakozásra..."
        $logintest = [Telnet]::InvokeCommands("")
        $login = $logintest | Select-String -Pattern "#", ">"
        if (!$login -or !$logintest)
        {
            Out-Result -Text "A megadott felhasználónév: $([Telnet]::felhasznalonev), vagy a hozzá tartozó jelszó nem megfelelő, esetleg a(z) $($script:config.switch) címen nincs elérhető switch" -Tag "conerr" -Level "err"
            $login = $false
        }
        else
        {
            Add-Log -Text "A(z) $([Telnet]::felhasznalonev) sikeresen kapcsolódott a(z) $($Script:config.switch) switchez" -Tag "consuccess"
            $login = $true
        }
        if($logintest | Select-String -Pattern ">")
        {
            [Telnet]::nonroot = $true
        }
        return $login
    }

    Static [Object]InvokeCommands($parancsok)
    {
        $socket = $null
        $result = ""
        if([Telnet]::nonroot)
        {
            [String[]]$commands = @([Telnet]::felhasznalonev, [Telnet]::jelszo, "enable", [Telnet]::jelszo)
        }
        else
        {
            [String[]]$commands = @([Telnet]::felhasznalonev, [Telnet]::jelszo)
        }
    
        foreach ($parancs in $parancsok)
        {
            $commands += $parancs
        }
    
        try
        {
            $socket = New-Object System.Net.Sockets.TcpClient($script:config.switch, $script:config.port)
        }
        catch
        {
            Show-Debug "Socket HIBA"
            $result = $false
        }
    
        if($socket)
        {
            $stream = $socket.GetStream()
            $writer = New-Object System.IO.StreamWriter($stream)
            $buffer = New-Object System.Byte[] 1024
            $encoding = New-Object System.Text.ASCIIEncoding
            foreach ($command in $commands)
            {
                $writer.WriteLine($command)
                $writer.Flush()
                [Telnet]::Allapot()
                $read = $Stream.read($buffer, 0, 1024)
                $kiolvasottsor = ($encoding.GetString($buffer, 0, $read))
                Show-Debug $kiolvasottsor
                $result += $kiolvasottsor
            }
    
    <#      Start-Sleep -Milliseconds $script:config.waittime
    
            while($stream.DataAvailable)
            {
                $read = $Stream.read($buffer, 0, 1024)
                $result += ($encoding.GetString($buffer, 0, $read))
            }
#>
        }
        else
        {
            $result = $false
        }
        return $result
    }

    Allapot()
    {
        $szoveg = "Parancs switchen futtatása folyamatban"
        $wait = $Script:config.waittime / 250
        $pont = ""
        for($i = 0; $i -lt $wait; $i++)
        {
            $pont += "."
            Out-Result "$szoveg$pont" -Overwrite -NoNewLine
            Start-Sleep -Milliseconds 250
        }
    }
}

#-#-#-#-#-#-#-#-#-#-#-#-#-#-#-#-#-#-#-#-#-#-#-#-#-#-#-#-#-#-#-#-#-#-#-#-#-#-#-#-#-#-#-#-#-#-#-#-#-#
#-#-#                                    FÜGGVÉNYEK                                           #-#-#
#-#-#-#-#-#-#-#-#-#-#-#-#-#-#-#-#-#-#-#-#-#-#-#-#-#-#-#-#-#-#-#-#-#-#-#-#-#-#-#-#-#-#-#-#-#-#-#-#-#

##  Importáló  függvények  ##
#    Függvények bemeneti    #
##  adatok begyűjtéséhez   ##
#############################

# Tiszta
function Import-ADObjects
{
    ###############################################################
    #
    # Leírás:       AD objektumokat importáló függvény. A bemenethez kötelezően az OrganizationalUnitot,
    #               és pontosan egyet a Computers, Users, Groups hármasból kell megadni. A függvény
    #               nem ellenőrzi, hogy az OrganizationalUnit DistinguishedName formátumban van-e,
    #               viszont a hibásan megadott OrganizationalUnit értelemszerűen kivételt fog dobni
    #               a job eredményének lekérésekor.
    #
    # Bemenet:      -OrganizationalUnit:    a lekérdezendő OU elérési útja DistinguishedName formátumban, kötelező megadni
    #               -ObjType:               a lekérdezendő objektum típusa, kötelező megadni
    #               -Aktiv:                 az x napon belül aktív felhasználók, nem kötelező megadni
    #               -Passziv:               az x napon belül nem aktiv felhasználók, nem kötelező megadni
    #               -Engedelyezve:          kapcsoló, csak az engedélyezett objektumok lekérése, nem kötelező megadni
    #               -Letiltva:              kapcsoló, csak a letiltott objektumk lekérése, nem kötelező megadni
    #
    # Kimenet:      AD objektumokat tartalmazó tömb, vagy Bool $False
    #
    # Függőségek:   * Out-Result
    #               * Show-JobInProgress
    #
    ###############################################################
    
    param(
        [Parameter(Mandatory=$true, ValueFromPipeline=$true)]$OrganizationalUnit,
        [Parameter(Mandatory=$true, ValueFromPipeline=$true)][ValidateSet("Computers", "Users", "Groups")]$ObjType,
        [Parameter(Mandatory=$false, ValueFromPipeline=$true)]$Aktiv,
        [Parameter(Mandatory=$false, ValueFromPipeline=$true)]$Passziv,
        [Switch]$Engedelyezve,
        [Switch]$Letiltva
    )

    Begin
    {
        switch ($ObjType) {
            Computers {
                $parancs = "Get-ADComputer"
                $objtip = "számítógépeinek"
                }
            Users {
                $parancs = "Get-ADUser"
                $objtip = "felhasználóinak"
                }
            Groups {
                $parancs = "Get-ADGroup"
                $objtip = "csoportjainak"
                }
        }

        $napszam = 0
        $filter = "-Filter *" # Alapeset, ha nem lenne semmilyen filter beállítva
        if(!($ObjType -eq "Groups") -and ($Aktiv -or $Passziv -or $Letiltva -or $Engedelyezve))
        {
            if(($Aktiv -and $Passziv) -or ($Letiltva -and $Engedelyezve)) # Egymásnak ellenmondó filterek tiltottak
            {
                Out-Result -Text "Az Aktiv és Passziv illetve a Letiltva és Engedélyezve kapcsolók nem használhatóak együtt! Az eredmények nem lesznek szűrve!" -Level "err"
            }
            else
            {
                $filter = "-Filter {"
                if($Aktiv)
                {
                    $filter += "LastLogonTimeStamp -gt `$time" # A backtickre azért van szükség, hogy csak az invoke idején helyettesítődjön be a $time változó
                    $napszam = $Aktiv
                }
                elseif($Passziv)
                {
                    $filter += "LastLogonTimeStamp -lt `$time" # A backtickre azért van szükség, hogy csak az invoke idején helyettesítődjön be a $time változó
                    $napszam = $Passziv
                }

                if(($Aktiv -or $Passziv) -and ($Letiltva -or $Engedelyezve)) # Ha mindkét filter kapcsoló kiválasztásra került
                {
                    $filter += " -and "
                }

                if($Engedelyezve)
                {
                    $filter += 'Enabled -eq "True"'
                }
                elseif($Letiltva)
                {
                    $filter += 'Enabled -eq "True"'
                }

                $filter += "}" # A filter szekciót lezáró zárójel
            }
        }
        elseif ($ObjType -eq "Groups") # Ha csoportot választottunk, nincs értelme egyik filternek sem
        {
            $filter = ""
        }

        $parancs += " -SearchBase '$OrganizationalUnit' $filter"
    }

    Process
    {
        $job = Start-Job -ScriptBlock { $time = (Get-Date).Adddays(-($args[1])); Invoke-Expression $args[0] } -ArgumentList $parancs, $napszam
        try
        {
            $objlista = Show-JobInProgress -Text "A(z) $($Script:config.ounev) OU $objtip eszközeinek begyűjtése" -Job $job
        }
        catch
        {
            Out-Result -Text "Ismeretlen hiba történ a $($Script:config.ounev) OU $objtip lekérésekor" -Level "err" -Tag "err" -Overwrite
            $objlista = $false
        }
        Return $objlista
    }
}

# Tiszta
function Import-IPaddresses
{
    ###############################################################
    #
    # Leírás:       IP tartományt importáló függvény. A felhasználótól bekéri a használni kívánt
    #               IP tartomány első és utolsó tagját, majd megkérdezi, hogy a két cím között
    #               ki akarunk-e hagyni tartomány. Ha igen, ott is bekéri az első és utolsó IP címet.
    #               A címek bevitelét folyamatosan ellenőrzi, illetve azt is ellenőrzi az összes
    #               cím megadását követően, hogy valós tömb állítható-e elő a megadott tartományokból.
    #               Ezt követően legyártja az [IPcim] objektumokat tartalmazó tömböt.
    #
    # Bemenet:      Nincs
    #
    # Kimenet:      [IPcim] objektumokat tartalmazó tömb
    #
    # Függőségek:   * Out-Result
    #               * IPcim osztály
    #
    ###############################################################
    
    $elsoIP = $null
    $utolsoIP = $null
    $elsokihagyott = $null
    $utolsokihagyott = $null

    do
    {
        Show-Cimsor "IP TARTOMÁNY ELLENŐRZŐ"

        Write-Host "Kérlek add meg a lekérdezni kívánt IP tartomány első IP címét!"
        $elsoIP = New-Object IPcim(Read-Host -Prompt "Első IP cím")
        Write-Host "Kérlek add meg a lekérdezni kívánt IP tartomány utolsó IP címét!"
        $utolsoIP = New-Object IPcim(Read-Host -Prompt "Utolsó IP cím")
        Write-Host "Szeretnél kihagyni egy megadott tartományt a két IP cím között?`nAdd meg a kihagyni kívánt tartomány első IP címét, ha igen, üss Entert, ha nem!"
        $valassz = Read-Host -Prompt "Válassz"
        if($valassz -and ([IPcim]::Checkpattern($valassz))) # Ha van input, ÉS megfelel a helyes IP formátumnak, bekérjük a következőt
        {
            $elsokihagyott = New-Object IPcim($valassz)
            Write-Host "Kérlek add meg az utolsó kihagyni kívánt IP címet!"
            $utolsokihagyott = New-Object IPcim(Read-Host -Prompt "Utolsó kihagyott IP cím")
        }
        elseif($valassz -and !([IPcim]::Checkpattern($valassz)))
        {
            Out-Result -Text "Nem érvényes IP címet adtál meg, nem lesz kihagyott tartomány a két IP között!" -Level "warn"
            $elsokihagyott = $False
        }
        else
        {
            $elsokihagyott = $False
        }
        
        $ipdarab = $elsoIP.Count($utolsoIP) # Megszámoltatjuk az IP tartományt a kihagyás nélkül
        if($elsokihagyott) # Ha van kihagyás, megszámoltatjuk vele a ténylegesen használt IP címek számát
        {
            $kihagy = $elsokihagyott.Count($utolsokihagyott)
            $ipdarab = $ipdarab - $kihagy
        }

        if ($elsoIP.ToString() -eq $utolsoIP.ToString()) # Ha az első és utolsó IP megegyezik, nincs mit importálni
        {
            Out-Result -Text "A megadott IP címek megegyeznek! Egy billentyű leütését követően add meg újra lekérdezni kívánt tartományt!" -Level "warn"
            Get-Valasztas
            $elsoIP = $False
        }
        elseif($ipdarab -lt 1) # Ha valamiért úgy sikerült paramétereznünk, hogy nincs mit importálni, a ciklus újraindul
        {
            Out-Result -Text "A megadott tartományban nincs egyetlen IP cím sem! Így a lekérdezés nem folytatható le!`nEgy billentyű leütését követően kérlek add meg újra a lekérdezni kívánt tartományt!" -Level "warn"
            Get-Valasztas
            $elsoIP = $False
        }
        elseif($ipdarab -gt 254)
        {
            Out-Result -Text "A megadott tartományban $ipdarab darab IP cím található. Egészen biztos vagy benne, hogy ennyi eszközt szeretnél egyszerre lekérdezni?`nAz összes cím lekérdezése hosszú időt vehet igénybe!"
            $valassz = Get-Valasztas -YesNo
            if(!$valassz)
            {
                $elsoIP = $False
            }
        }
        elseif($elsokihagyott) # Ha van kihagyás, ellenőrizzük, hogy érvényes tartományokról beszélünk-e
        {
            if ($elsoIP.BiggerThan($elsokihagyott) -or $utolsokihagyott.BiggerThan($utolsoIP) -or $elsokihagyott.BiggerThan($utolsokihagyott))
            {
                Write-Host "A megadott tartományban nincs egyetlen IP cím sem! Így a lekérdezés nem folytatható le!`nEgy billentyű leütését követően kérlek add meg újra a lekérdezni kívánt tartományt!" -ForegroundColor Red
                Get-Valasztas
                $elsoIP = $False
            }
        }
    }while(!$elsoIP)

    if($elsokihagyott)
    {
        $eszkozok = $elsoIP.RangeKihagyassal($utolsoIP, $elsokihagyott, $utolsokihagyott)
    }
    else
    {
        $eszkozok = $elsoIP.Range($utolsoIP)
    }

    return $eszkozok
}

# Tiszta
function Import-SQLiteData
{
    ###############################################################
    #
    # Leírás:       Tömböt az SQLite adatbázisból importáló függvény. Ellenőrzi, hogy a kapott névvel
    #               létezik-e már adattábla, és ha igen, felajánlja a felhasználónak, hogy azt a táblát
    #               használja az adatok frissen importálása helyett.
    #               Amennyiben a felhasználó az újraimportálás mellett dönt, úgy a függvény eldobja
    #               a jelenlegi adattáblát, amennyiben a meglévő adattáblát használná, elvégzi az SQL importálást.
    #               A függvény használatának nagy előnye, hogy rugalmasan képes működni, függetlenül attól,
    #               hogy az importálni kívánt adattáblában hány attribútum található.
    #                                           !!!! FIGYELEM !!!!
    #               A függvény NEM végez semmilyen összevetést a kimenetnek szánt objektum, és az adattáblából vett
    #               adatok között. Tehát ha a táblában van egy olyan oszlop, ami az objektum osztályában nincs,
    #               a függvény egyszerűen létrehozza!
    #                                           !!!! FIGYELEM 2 !!!!
    #               A használt objektum osztályának rendelkeznie KELL paraméter nélküli konstruktorral!
    #
    # Bemenet:      -EgyediNev:     az ellenőrizendő adattábla neve, kötelező megadni
    #               -ObjType:       a visszadott objektumok típusa, kötelező megadni
    #               -Silent:        kapcsoló, használatával kikapcsolható a felhasználó megkérdezése az importról
    #
    # Kimenet:      Objektumokat tartalmazó tömb, vagy Bool $False
    #
    # Függőségek:   * Get-Valasztas
    #               * Out-Result
    #               * SQL osztály
    #
    ###############################################################
    param(
        [Parameter(Mandatory=$true)]$EgyediNev,
        [Parameter(Mandatory=$true)]$ObjType,
        [Switch]$Silent
    )

    $SQLtableName = [SQL]::SetTableName($ObjType, $EgyediNev)
    try # Lekérjük a névkonvenció szerinti adattábla teljes tartalmát
    {
        $SQLimportData = $script:runtime.sql.QueryTable("Select * From $SQLtableName") 
    }
    catch
    {
        $returnObjArr = $False # Ha a tábla lekérése kivételt dob, $False visszatérési érték beállítása
    }
    

    if($SQLimportData -and $SQLimportData.Rows.Count -gt 0) # Ha van kiolvasott adat, kezdjük meg a PS objektumokká alakítását
    {
        $useSQLdata = $true
        if(!$Silent) # Ha nincs beállítva a Silent kapcsoló, kérdezzük meg a Usert, hogy az SQL tartalmat használja-e
        {
            Write-Host "A kiválasztott adattábla tartalmaz adatokat. Szeretnéd ezeket használni?"
            $useSQLdata = Get-Valasztas -YesNo
        }
        
        if($useSQLdata)
        {
            $returnObjArr = New-Object System.Collections.ArrayList($null)

            ForEach($Row in $SQLimportData.Rows) # Lekérjük a sorokat az adatbázis objektumból
            {
                $toInvoke = "New-Object $ObjType" # Csúnya megoldás stringként megadni a típus nevét, de működik
                try # Tekintve, hogy nincs típusellenőrzés, fel kell készülni, hogy nem létező típust kap bemenetként a függvény
                {
                    $Record = Invoke-Expression $toInvoke # Az invoke parancs így a stringben kapott típusú objektumot hozza létre
                }
                catch
                {
                    Out-Result "A megadott objektumtípus: [$ObjType] nem található a jelen környezetben, vagy nincs paraméter nélküli konstruktora!" -Level "err" -Tag "err"
                    $returnObjArr = $False
                    Break
                }
                
                ForEach($Col in $SQLimportData.Columns.ColumnName) # Végigmegyünk az oszlopokon
                {
                    # Az SQLite-ból sem a null, sem a bool értékek nem megfelelő típussal érkeznek
                    # ezért az importálás előtt megfelelő típusúvá konvertáljuk őket
                    $value = $Row.$Col
                    if(($value -eq "null") -or ($value.GetType() -eq [DBNull]))
                    {
                        $value = $null
                    }
                    elseif($value -eq "True")
                    {
                        $value = $True
                    }
                    elseif($Row.$Col -eq "False")
                    {
                        $value = $False
                    }

                    # A konverziók után az oszlop nevének megfelelő értéket hozzáadjuk
                    # az objektum azonos nevű attribútumához
                    # A -Force kapcsoló nélkül ütközést érzékelne, de ez nem okoz problémát
                    Add-Member -InputObject $Record -NotePropertyName $Col -NotePropertyValue $value -Force
                }

                $returnObjArr.Add($Record) > $null # Az elkészült objektumot hozzáadjuk a visszaadott tömbhöz
            }
        }
        else
        {
            $script:runtime.sql.DropTable($SQLtableName)
            $returnObjArr = $False
        }
    }

    if(!$returnObjArr)
    {
        return $returnObjArr
    }
    else
    {
        return ,$returnObjArr # A vessző NEM elírás, enélkül objektumot ad vissza a függvény, nem ArrayList-et
    }
}

function Import-FromCSV
{
    ###############################################################
    #
    # Leírás:       Tömböt CSV fájlból importáló függvény. A bemenetként kapott CSV fájlból a bemenetként kapott
    #               típusú objektumokat próbálja létrehozni.
    #               A függvény használatának nagy előnye, hogy tökéletesen független a bemenetként használt
    #               CSV-ben található oszlopok számától. Egyoszlopos CSV-kkel ugyanúgy működik,
    #               mint tízoszloposokkal.
    #                                           !!!! FIGYELEM !!!!
    #               A függvény NEM végez semmilyen összevetést a kimenetnek szánt objektum, és a CSV fájlból vett
    #               adatok között. Tehát ha a CSV fájlban van egy olyan oszlop, ami az objektum osztályában nincs,
    #               a függvény egyszerűen létrehozza!
    #                                           !!!! FIGYELEM 2 !!!!
    #               A használt objektum osztályának rendelkeznie KELL paraméter nélküli konstruktorral!
    #
    # Bemenet:      -ObjType:       a visszadott objektumok típusa, kötelező megadni
    #
    # Kimenet:      Objektumokat tartalmazó tömb, vagy Bool $False
    #
    # Függőségek:   * Out-Result
    #
    ###############################################################

    param([Parameter(mandatory=$True)]$ObjType)
    
    try
    {
        $csvdata = Import-Csv -Path $Script:config.csvin -Delimiter ";"
    }
    catch
    {
        $returnObjArr = $false
        Out-Result -Text "A bemenetként megadott CSV fájl nem található" -Level "warn" -Tag "fileerr" -Overwrite
    }

    if($csvdata)
    {
        $returnObjArr = New-Object System.Collections.ArrayList($null)
        ForEach($Row in $csvdata) # Lekérjük a sorokat a CSV fájlból
        {
            $toInvoke = "New-Object $ObjType" # Csúnya megoldás stringként megadni a típus nevét, de működik
            try # Tekintve, hogy nincs típusellenőrzés, fel kell készülni, hogy nem létező típust kap bemenetként a függvény
            {
                $Record = Invoke-Expression $toInvoke # Az invoke parancs így a stringben kapott típusú objektumot hozza létre
            }
            catch
            {
                Out-Result "A megadott objektumtípus: [$ObjType] nem található a jelen környezetben, vagy nincs paraméter nélküli konstruktora!" -Level "err" -Tag "err"
                $returnObjArr = $False
                Break
            }

            ForEach($Col in $Row.PsObject.Properties) # Végigmegyünk az oszlopokon
            {
                # A CSV fájlból értelemszerűen csak string típusú objektumok érkeznek,
                # így a $null, $true, és $false átalakításokat most kell elvégezni
                $value = $Col.Value
                if($value -eq "null" -or $value -eq "")
                {
                    $value = $null
                }
                elseif($value -eq "True")
                {
                    $value = $True
                }
                elseif($Row.$Col -eq "False")
                {
                    $value = $False
                }

                # A konverziók után az oszlop nevének megfelelő értéket hozzáadjuk
                # az objektum azonos nevű attribútumához
                # A -Force kapcsoló nélkül ütközést érzékelne, de ez nem okoz problémát
                Add-Member -InputObject $Record -NotePropertyName $Col.Name -NotePropertyValue $value -Force
            }
            $returnObjArr.Add($Record) > $null # Az elkészült objektumot hozzáadjuk a visszaadott tömbhöz
        }

        if($returnObjArr.Count -eq 0)
        {
            $returnObjArr = $false
            Out-Result -Text "A CSV fájl nem tartalmaz értelmezhető adatot" -Level "warn" -Tag "fileerr"
        }
    }
    if(!$returnObjArr)
    {
        Return $returnObjArr
    }
    else
    {
        return ,$returnObjArr
    }
}

##   Lekérő függvények   ##
#  Függvények információ  #
##      lekérésére       ##
###########################

# Tiszta
function Get-UserLevel
{
    ###############################################################
    #
    # Leírás:       Lusta függvény. Bekéri a jelenlegi user jogosultságait, és $True-t ad vissza, ha admin szintű
    #
    # Bemenet:      Nincs
    #
    # Kimenet:      $True ha a programot admin joggal futtatják, $False, ha nem
    #
    # Függőségek:   Nincs
    #
    ###############################################################

    $currentuser = New-Object Security.Principal.WindowsPrincipal([Security.Principal.WindowsIdentity]::GetCurrent())
    $admin = $currentuser.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)

    return $admin
}

function Get-NameByIP
{
    param ($IPaddress)
    try
    {
        $namesplit = ([System.Net.DNS]::GetHostEntry($IPaddress)).HostName
        $kimenet = $namesplit.Split(".")
        $name = $kimenet[0]
    }
    catch [System.Net.Sockets.SocketException]
    {
        $name = "Nem elérhető"
    }

    return $name
}

function Get-MegjelenoNev
{
    param($clientusername)

    try
    {
        $bejelentkezesinev = $clientusername.Split("\") # A név STN\bejelenkezési név formátumban jön. Ezt szétbontjuk, hogy megkapjuk a bejelentkezési nevet
        $user = Get-ADUser $bejelentkezesinev[1] # A bejelentkezési névvel lekérjük a felhasználó adatait
        return $user.Name
    }
    catch
    {
        return $clientusername
    }
}

function Get-GepNev
{
    param ($gepip)

    try
    {
        $namesplit = ([System.Net.DNS]::GetHostEntry($gepip)).HostName
        $kimenet = $namesplit.Split(".")
        return $kimenet[0]
    }
    catch [System.Net.Sockets.SocketException]
    {
        return $gepip
    }
}

## Megjelenítő  függvények ##
#    Függvények kimenet     #
##  egyszerű formázásához  ##
#############################

function ConvertFrom-BoolToString
{
    param($ertek)

    if ($ertek)
    {
        Write-Host "Bekapcsolva" -ForegroundColor Green
    }
    else
    {
        Write-Host "Kikapcsolva" -ForegroundColor Red
    }
}

# Tiszta
function Show-Cimsor
{
    ###############################################################
    #
    # Leírás:       Lusta függvény. Törli a képernyőt, és kiírja a program, valamint az almenü nevét
    #
    # Bemenet:      -Almenu:        Almenü neve, kötelező megadni
    #
    # Kimenet:      Nincs
    #
    # Függőségek:   Nincs
    #
    ###############################################################

    param([Parameter(Mandatory=$true)]$Almenu)
    Clear-Host
    Write-Host "HÁLÓZATKEZELÉSI ESZKÖZTÁR`n$Almenu`n"
}

# Tiszta
function Show-Debug
{
    ###############################################################
    #
    # Leírás:       Lusta függvény. Nem tetszik a PowerShell alapértelmezett debug módja
    #               szóval írtam rá ezt a függvényt. Olyan üzeneteket jelenít meg,
    #               amik csak bekapcsolt debug mód mellett jelennek meg.
    #
    # Bemenet:      -Text:        Debug üzenet, kötelező megadni
    #
    # Kimenet:      Nincs
    #
    # Függőségek:   Nincs
    #
    ###############################################################

    param([Parameter(Mandatory=$true)]$Text)

    if($Script:config.debug)
    {
        Write-Host "[DEBUG] $Text" -ForegroundColor Blue
    }
}

# Tiszta
function Set-Logname
{
    ###############################################################
    #
    # Leírás:       Lusta függvény. A logfile átnevezésére szolgál.
    #
    # Bemenet:      -Filename:      Az új logfile neve
    #
    # Kimenet:      Nincs
    #
    # Függőségek:   Nincs
    #
    ###############################################################

    param([Parameter(Mandatory=$true)]$Filename)

    $Script:config.logfile = "$Filename.log"
}

# Tiszta
function Test-Ping
{
    ###############################################################
    #
    # Leírás:       A Test-Connection-nél egy gyorsabb kapcsolati állapot ellenőrző függvény.
    #
    # Bemenet:      -NetDevice:      Az ellenőrizni kívánt eszköz IP címe, vagy neve, kötelező megadni
    #
    # Kimenet:      Bool érték az eszköz elérhetőségéről
    #
    # Függőségek:   Nincs
    #
    ###############################################################
    param ([Parameter(Mandatory=$True, ValueFromPipeline=$True)]$NetDevice)

    Begin
    {
        $ping = New-Object System.Net.NetworkInformation.Ping
        $response = $False
    }
    
    Process
    {
        if (!$script:runtime.pingoptions)
        {
            $script:runtime.pingoptions = New-Object System.Net.NetworkInformation.PingOptions
            $script:runtime.pingoptions.TTL = 64
            $script:runtime.pingoptions.DontFragment = $true
        }

        for($i = 0; $i -lt 4; $i++) # Az egyszeri ping néha fals negatívot ad, ezért 4 kísérletet adunk neki a valós False-ra.
        {
            try
            {
                $reply = $ping.Send($NetDevice,20,16,$script:runtime.pingoptions)
            }
            catch { }

            if ($reply.status -eq "Success")
            {
                $response = $True
                Break
            }
        }
        return $response
    }
}

# Tiszta
function Compare-Subnets
{
    ###############################################################
    #
    # Leírás:       Alhálózat összehasonlító függvény. Kiszámolja, hogy két IP cím
    #               az adott maszkhosszúsággal lehet-e egy alhálózaton.
    #               A függvény elgondolása, hogy az IP cím negyedekre osztott tagjait veszi alapul.
    #               Először ellenőrzi, hogy a maszk által teljesen fedett negyedek megegyeznek-e,
    #               majd, ha azok megegyeztek, elemzi a részlegesen fedett negyedet is (amennyiben van).
    #               A függvény második fele KIZÁRÓLAG a részlegesen fedett negyeddel foglalkozik,
    #               ha az alapján a két cím lehet egy alhálózaton, az esetleges fedetlen negyed(ek)
    #               ellenőrzésére már nincs szükség.
    #
    # Bemenet:      -Local:     A kiinduló eszköz IP címe, kötelező megadni
    #               -Remote:    A második eszköz IP címe, kötelező megadni
    #               -Mask:      A maszk hossza bitben megadva
    #
    # Kimenet:      Bool érték arról, hogy a két eszköz lehet-e egy subneten, vagy sem
    #
    # Függőségek:   Nincs
    #
    # Megjegyzés:   SOHA többé kommentelés nélkül hagyni egy funkciót, FŐLEG, ha matematikai!!!
    #
    ###############################################################

    param (
        [Parameter(Mandatory=$True)]$Local,
        [Parameter(Mandatory=$True)]$Remote,
        [Parameter(Mandatory=$True)]$Mask
        )

    $masktag = [Math]::truncate($Mask / 8) # Megkapjuk, hogy hány negyedet fed le teljesen a maszk
    $reszleges = $Mask % 8 # Megnézzük, hogy van-e részlegesen fedett negyed is
    $samesubnet = $true

    for ($i = $masktag - 1; $i -ge 0; $i--) # Először végigmegyünk a maszk által teljesen vedett negyedeken
    {
        if ((($Local).Split("."))[$i] -ne ((($remote).Split("."))[$i])) # Ha valamelyik teljesen fedett negyed eltér, biztosan különböznek a subnetek
        {
            $samesubnet = $false
            Break
        }
    }
    if($samesubnet -and $reszleges -ne 0) # Ha minden teljesen fedett negyed megegyezett, megnézzük a részlegesen fedettet is
    {
        # Kiszámoljuk, hogy az adott subnet adott tagjába hány ip tartozhat (tehát NEM a teljes subnetbe).
        # Alapból 2^8 lehetne, de ebből le kell vonni a maszk által fedett biteket ($reszleges)
        $subnetsize = 8 - $reszleges
        $samesubnet = $false
        [int]$local = (($local).Split("."))[$masktag] # Mivel 0-tól indexelünk, a $masktag-edik negyed a részlegesen fedett
        [int]$remote = (($remote).Split("."))[$masktag] # Mivel 0-tól indexelünk, a $masktag-edik negyed a részlegesen fedett
        if($local -eq $remote) # Ha a részlegesen fedett negyed megegyezik, biztosan egy alhálózaton vannak
        {
            $samesubnet = $True
        }
        else
        {
            $subnetsize = [Math]::Pow(2, $subnetsize) # A lehetséges IP címek számát a 2 fedetlen bitedik hatványára emelve kapjuk meg
            [int]$subnetstart = $local - ($local % $subnetsize) # Az IP címből kivonjuk a lehetséges IP címek maradékát, hogy meglegyen az első cím
            [int]$subnetend = $subnetstart + $subnetsize - 1 # Csak hozzáadjuk az elérhető ipcím számot a subnet első IP-jéhez
            if($remote -ge $subnetstart -and $remote -le $subnetend) # Ha a remote a subnet első és utolsó IP-je közé esik, egy subneten vannak
            {
                $samesubnet = $true
            }
        }
    }
    return $samesubnet
}

# Tiszta
function Format-TracertCommand
{
    ###############################################################
    #
    # Leírás:       A switchen futtatandó layer2 tracert parancsot létrehozó függvény.
    #               Osztályból lett átírva függvénnyé, mert sosem használta ki az osztály plusz képességeit
    #               a könnyebben kezelhető függvényekkel szemben.
    #
    # Bemenet:      -Local:         A kiindulóként használt [Local] objektum, kötelező megadni
    #               -Remote:        A megtalálni kívánt [Remote] objektum, kötelező megadni
    #               -Hibajavitas:   Kapcsoló, ezzel választható ki, hogy 
    #
    # Kimenet:      A switchen futtatandó parancs, vagy $null
    #
    # Függőségek:   Nincs
    #
    ###############################################################
    param(
        [Parameter(Mandatory=$true)]$Local,
        [Parameter(Mandatory=$true)]$Remote,
        [Switch]$Hibajavitas
    )

    $result = $null
    do
    {
        $Remote.GetMAC()
        if(!($Remote.IPaddress -eq $Local.IPaddress))
        {
            if($Remote.MACaddress)
            {
                $result = "traceroute mac $($Local.MACaddress) $($Remote.MACaddress)"
            }
        }
        else
        {
            Out-Result -Text "A kereséshez kiindulásként használt $($local.IPaddress) eszköz IP címe megegyezik a keresett eszköz ($($remote.IPaddress)) IP címével. A keresés nem hajtható végre" -Tag "ipmatch" -Level "err"
        }

        if($Hibajavitas -and !$result)
        {
            $Remote.AdatBeker()
        }
    } while($Hibajavitas -and !$result)

    Return $result
}

#####
##
##  Összetett kisegítőfüggvények. Ezek a függvényeket összetettebb,
##  vagy akár egyszerre több feladatokat látnak el
##
#####

function Get-Local
{
    ###############################################################
    #
    # Leírás:       Beállítja a kiindulóként használt eszközt. A kikommentelt rész felel azért,
    #               hogy más subneten lévő eszközök megkereséséhez is lehessen megadni egy kiinduló eszközt.
    #               Jelenleg az a rész NEM működik rendesen, úgyhogy most inkább arra koncentrálok,
    #               hogy azonos alhálózatban tisztán és átláthatóan működjön a script.
    #
    # Bemenet:      -Local:     A kiinduló eszköz IP címe, kötelező megadni
    #               -Remote:    A második eszköz IP címe, kötelező megadni
    #               -Mask:      A maszk hossza bitben megadva
    #
    # Kimenet:      Bool érték arról, hogy a két eszköz lehet-e egy subneten, vagy sem
    #
    # Függőségek:   Nincs
    #
    # Megjegyzés:   SOHA többé kommentelés nélkül hagyni egy funkciót, FŐLEG, ha matematikai!!!
    #
    ###############################################################
    param(
        [Parameter(Mandatory=$true)]$Local,
        [Parameter(Mandatory=$true)]$Remote
    )

    Show-Debug "Get-Local függvény meghívva"
    if (Compare-Subnets $Local.IPaddress $Remote.IPaddress $Local.Mask)
    {
        Show-Debug "A helyi, és elérni kívánt eszköz egy subneten van"
        $localtouse = $Local
    }
    <#elseif($local:config.masvlanon)
    {
        Show-Debug "A helyi, és távoli eszköz nem egy subneten van"
        if (($script:diffsubnetek.Length -lt 1) -and $remote.MACaddress)
        {
            Show-Debug "Első új subnet, új távoli kiinduló eszközzel"
            $script:remotelocal.Add([Local]::New($remote.Eszkoznev)) > $null
            $script:diffsubnetek.Add([MasVLAN]::New($script:remotelocal[0])) > $null
            $script:pinggepids.Add($i) > $null
            $eszkoz.SetIP($script:remotelocal[0].IPaddress)
            $localtouse = $script:remotelocal[0]
        }
        elseif ($remote.MACaddress)
        {
            $createnew = $true
            Show-Debug "A távoli eszköz MAC címe ismert"
            foreach ($subnet in $script:diffsubnetek)
            {
                if ($remote.IPaddress -match $subnet.subnet)
                {
                    if($subnet.tracegep.Megbizhato)    
                    {
                        Show-Debug "Használni kívánt subnet kiválasztva"
                        $localtouse = $subnet.tracegep
                        $createnew = $false
                        Break
                    }
                    else
                    {
                        Show-Debug "Meglévő subnet, traceeléshez használt gép lecserélése"
                        $script:remotelocal.Add([Local]::New($remote.Eszkoznev)) > $null
                        $subnet.tracegep = $script:remotelocal[-1]
                        $eszkoz.SetIP($script:remotelocal[-1].IPaddress)
                        $pinggepids.Add($i) > $null
                        $localtouse = $remotelocal[-1]
                    }
                }
            }
            if ($createnew)
            {
                Show-Debug "Új subnet, új távoli kiinduló eszközzel"
                $script:remotelocal.Add([Local]::New($remote.Eszkoznev)) > $null
                $script:diffsubnetek.Add([MasVLAN]::New($script:remotelocal[-1])) > $null
                $eszkoz.SetIP($script:remotelocal[-1].IPaddress)
                $pinggepids.Add($i) > $null
                $localtouse = $remotelocal[-1]
            }
        }
    }#>
    else
    {
        Show-Debug "Eltérő VLANok! A beállításoknak megfelelően az eszköz helyének megkeresésével nem próbálkozom meg!"
        Out-Result -Text "A(z) $($remote.Eszkoznev) más VLANon van, mint a jelenlegi eszköz. A beállításoknak megfelelően kihagyásra kerül" -Level "warn" -Tag "notmatchingsub" -Overwrite
        $localtouse = $false
    }
    return $localtouse
}

function Out-LocalToUse
{
    param($eszkoz, $localtouse, $csv)

    Show-Debug "A kiinduló eszköz adatainak kitöltése"
    $eszkoz.SetSwitchNev($localtouse.SwitchNev)
    $eszkoz.SetSwitchIP($localtouse.SwitchIP)
    $eszkoz.SetPort($localtouse.Port)
    $eszkoz.SetIP($localtouse.IPaddress)
    $eszkoz.SetMAC($localtouse.MACaddress)
    $eszkoz.SetFelhasznalo()
    $eszkoz.Finished = $True
    $eszkoz.UpdateRecord()
    $csv.Sync($eszkoz, "IPaddress")
}

#####
##
##  Menüpontok. Ezeket a függvényeket hívják meg közvetlenül a főmenü menüpontjai
##
#####

######### ELLENŐRIZVE, KÉSZ !!!!!!!!!!!!!!!!!!!!!!!!!
function Get-DeviceLocation
{
    ###############################################################
    #
    # Leírás:       Egy komplett OU eszközeinek helyét megkereső függvény. Az eredményt a Global beállításoknak
    #               megfelelően menti egy CSV fájlba.
    #               A függvény ellenőrzi a program SQLite adatbázisában, hogy az adott OU-n futott-e már
    #               félbeszakadt ellenőrzés, és ha igen, felkínálja a felhasználónak, hogy azt az ellenőrzést
    #               folytassa, vagy indítson inkább egy újat.
    #               
    # Bemenet:      Nincs
    #
    # Kimenet:      AD-ból vett számítógépek switchport pontosságú helyét tartalmazó CSV fájl
    #
    # Függőségek:   * Show-Cimsor
    #               * Set-Logname
    #               * Get-Valasztas
    #               * Format-TracertCommand
    #               * Show-Menu
    #               * SQL osztály
    #               * Local osztály
    #               * Remote osztály
    #               * Telnet osztály
    #
    ###############################################################

    Show-Cimsor "Egyetlen eszköz megkeresése"
    Set-Logname "EszkozHely"
    $local = [Local]::New()
    do
    {
        $remote = [Remote]::New()

        if($remote.Elerheto())
        {
            $keresesiparancs = Format-TracertCommand -Local $local -Remote $remote -Hibajavitas
        }
        else
        {
            Write-Host "Add meg újra az IP címet, vagy nevet!" -ForegroundColor Red
        }
    }while(!$keresesiparancs -or !$remote.Elerheto())

    [Telnet]::Login()
    $eszkoz = [Eszkoz]::New($remote.IPAddress)
    $eszkoz.Lekerdez($keresesiparancs, $local, $remote, "(1/1)")
    if($eszkoz.Siker())
    {
        $consolout = $null
        foreach ($sor in $eszkoz.Sorok)
        {
            if ($sor | Select-String -pattern "=>")
            {
                $consolout += "$sor`n"
            }
        }
        Show-Cimsor "Eszköz fizikai helyének megkeresése"
        Write-Host "Az adatcsomagok útja erről az eszközről a(z) $($eszkoz.IPaddress) IP című eszközig:"
        Write-Host $consolout
        Write-Host "A keresett eszköz a(z) $($eszkoz.SwitchNev) $($eszkoz.SwitchIP) switch $($eszkoz.Port) portján található." -ForegroundColor Green
    }
    else
    {
        Write-Host "Helyi IP cím:           $($local.IPaddress) (ezt kell pingelni a switchről, ha a TraceRoute parancs 'Error: Source Mac address not found.' hibát ad."
        Write-Host "Keresett eszköz IP-je:  $($remote.IPaddress) (ezt kell pingelni a switchről, ha a TraceRoute parancs 'Error: Destination Mac address not found.' hibát ad."
        Write-Host "Keresési parancs:       $($keresesiparancs) (automatikusan a vágólapra másolva)`n"
        Set-Clipboard $keresesiparancs
    }
    Out-Result -Text "A folyamat végetért"
    Show-Menu -Exit -BackOne
}

######### ELLENŐRIZVE, JELEN FUNKCIÓJÁT TEKINTVE KÉSZ
function Get-ADcomputersLocation
{
    ###############################################################
    #
    # Leírás:       Egy komplett OU eszközeinek helyét megkereső függvény. Az eredményt a Global beállításoknak
    #               megfelelően menti egy CSV fájlba.
    #               A függvény ellenőrzi a program SQLite adatbázisában, hogy az adott OU-n futott-e már
    #               félbeszakadt ellenőrzés, és ha igen, felkínálja a felhasználónak, hogy azt az ellenőrzést
    #               folytassa, vagy indítson inkább egy újat.
    #               
    # Bemenet:      Nincs
    #
    # Kimenet:      AD-ból vett számítógépek switchport pontosságú helyét tartalmazó CSV fájl
    #
    # Függőségek:   * Show-Cimsor
    #               * Set-Logname
    #               * Import-ADObjects
    #               * Import-SQLiteData
    #               * Out-Result
    #               * Out-LocalToUse
    #               * Add-Log
    #               * Get-Valasztas
    #               * Start-Wait
    #               * Format-TracertCommand
    #               * Show-Menu
    #               * SQL osztály
    #               * CSV osztály
    #               * Local osztály
    #               * Remote osztály
    #               * Eszkoz osztály
    #               * Telnet osztály
    #
    ###############################################################

    Show-Cimsor "AD-BÓL VETT GÉPEK LISTÁJÁNAK LEKÉRDEZÉSE"
    Set-Logname "EszkozHely"

    $local = [Local]::New()
    $sajateszkoz = $null

    $ou = Select-OU # Kiválasztjuk az OU-t
    $ADgeplista = Import-SQLiteData -ObjType "Eszkoz" -EgyediNev $Script:config.ounev # Ellenőrizzük, hogy az adott OU-val volt-e folyamat

    if(!$ADgeplista) # Ha nem importáltunk objektumokat az SQLite adatbázisból, AD-ből importálunk
    {
        $ADgeplista = New-Object System.Collections.ArrayList($null)
        $gepek = Import-ADObjects -OrganizationalUnit $ou -ObjType Computers -Aktiv $Script:config.aktivnapok
        $aktualis = 0
        $ossz = $gepek.Count
        if($gepek)
        {
            Write-Host "Eszközök begyűjtése az AD-ból"
            foreach($gep in $gepek)
            {
                $aktualis++
                Out-Result "($($aktualis)/$($ossz))" -NoNewLine -Overwrite # Gyorsabb lenne kijelzés nélkül, de 5-10 másodperc is lehet a folyamat
                # Nem a legszebb, létre lehetne hozni az [Eszkoz] objektumokat a munkaciklusban is, de tisztább,
                # ha oda már importálási formától függetlenül azonos, [Eszkoz] objektumokat tartalmazó tömb érkezik
                $eszkoz = [Eszkoz]::New($gep.Name)
                if($gep -eq $gepek[0]) # Az első eszköz importálásánál létrehozzuk a táblát az adatbázisban
                {
                    $eszkoz.CreateTable($Script:config.ounev)
                }
                $eszkoz.AddRecord() # Hozzáadjuk az adatbázishoz az importált [Eszkoz] objektumot
                $ADgeplista.Add($eszkoz) > $null
            }
            Write-Host
        }
        else
        {
            $ADgeplista = $False
        }
    }
    
    if($ADgeplista)
    {
        [Telnet]::Login()
        Clear-Host
        Out-Result -Text "A(z) $($Script:config.ounev) OU gépeinek helyének lekérdezése megkezdődött" -Tag "begin"
        $csv = [CSV]::New("EszközHely", $Script:config.ounev)
        
        do
        {
            $templist = $ADgeplista.Clone() # Kell egy megegyező ArrayList, amiről foreach alatt törölni lehet objektumokat. A Clone() metódus nélkül csak referencia átadás történik
            $aktualis = 0
            $osszdarab = $ADgeplista.Count

            foreach ($eszkoz in $ADgeplista)
            {
                $aktualis++
                $allapot = "($($aktualis)/$($osszdarab))"
                Out-Result "$allapot A(z) $($eszkoz.Eszkoznev) eszköz lekérdezése folyamatban." -NoNewLine
                if (($eszkoz.Eszkoznev -eq $local.Gepnev) -and !$eszkoz.Finished) # Ellenőrizzük, hogy a listából vett gép nem-e ugyanaz, mint a sajátunk
                {
                    Out-Result "A megkeresni kívánt gép ($($eszkoz.Eszkoznev)) megegyezik a jelenlegi eszközzel ($($local.Gepnev)). A keresés nem hajtható végre" -Level "warn" -Tag "devnamematch" -Overwrite
                    [Eszkoz]$sajateszkoz = $eszkoz
                }
                elseif(!$eszkoz.Finished) # Ha a keresett gép nem egyezik a sajáttal, és nincs még készen, erre az ágra lépünk
                {
                    $remote = [Remote]::New($eszkoz.Eszkoznev) # Új [Remote] objektum
                    if($remote.Elerheto()) # Meghívjuk a [Remote] objektum állapot ellenőrzési metódusát
                    {
                        Show-Debug "A távoli eszköz elérhető"
                        $localtouse = Get-Local -Local $local -Remote $remote # Meghívjuk a függvényt, ami kiválasztja a VLAN-hoz tartozó, kiindulónak használt eszközt
                        if($localtouse) 
                        {
                            $keresesiparancs = Format-TracertCommand -Local $local -Remote $remote
                            Show-Debug $keresesiparancs
                        }
                        else # Ha nincs kiindulónak használt eszköz (pl mert más vlan-on van, mint a lekért) kilépünk
                        {
                            $keresesiparancs = $false
                        }
                        if($keresesiparancs) # Ha létre lehetett hozni parancsot, futtatjuk a lekérdezést
                        {
                            $eszkoz.SetTableName($Script:config.ounev) # Beállítjuk az [Eszkoz] objektumon, hogy melyik adattáblába próbálja beírni magát
                            $eszkoz.Lekerdez($keresesiparancs, $localtouse, $remote, $allapot)
                            if($eszkoz.Lekerdezes) # Ha sikeres volt a lekérdezés
                            {
                                Show-Debug "Lekérdezés sikeres"
                                $eszkoz.SetFelhasznalo() # Meghívjuk az [Eszkoz] metódusát, ami kikeresi a jelenlegi felhasználót
                                $csv.Sync($eszkoz, "Eszkoznev") # Az eredményt fájlba írjuk
                                $eszkoz.Finished = $True # Befejezettnek állítjuk be az objektumot
                                $eszkoz.UpdateRecord() # Frissítjük az adatbázist az [Eszkoz] adataival
                                $templist.Remove($eszkoz) # Kitöröljük a már kész [Eszkoz]-t a templist tömbből

                                Out-Result -Text "A(z) $($eszkoz.Eszkoznev) eszköz megtalálva a(z) $($eszkoz.SwitchNev) switch $($eszkoz.Port) portján" -Overwrite

                                if($sajateszkoz) # Kitöltjük a kiindulóként használt [Eszkoz]-t is adatokkal
                                {
                                    Out-LocalToUse $sajateszkoz $localtouse $csv
                                    $templist.Remove($sajateszkoz) # Kitöröljük a már kész [Eszkoz]-t a templist tömbből
                                }
                            }
                            elseif ($eszkoz.SwitchNev) # Ha a lekérdezés legalább a switch nevét megtalálta, részleges adatkitöltés történik
                            {
                                Show-Debug "Adatok részleges kitöltése"
                                $eszkoz.SetFelhasznalo()
                                $eszkoz.Finished = $False
                                $eszkoz.UpdateRecord()
                                $csv.Sync($eszkoz, "Eszkoznev")
                            }
                        }
                    }
                }
                else
                {
                    # Ide adatbázisból importálás utáni első ciklusban juthatunk, ha az adatbázisból vett eszközön
                    # $True-ra volt állítva a Finished attribútum
                    Out-Result -Text "A(z) $($eszkoz.Eszkoznev) eszköz korábban már ellenőrizve lett. Kihagyás" -Overwrite
                    $templist.Remove($eszkoz) # Kitöröljük a már kész [Eszkoz]-t a templist tömbből
                }
            }

            $ADgeplista = $templist.Clone() # A következő ciklusban már a frissített listával dolgozunk
            
            [System.GC]::Collect()

            # Ha nem vagyunk meg minden géppel, belépünk a késleltető ciklusba,
            # ami a fő ciklust pihenteti egy kicsit.
            if ($templist.Count -gt 0)
            {
                Out-Result -Text "A(z) $($Script:config.ounev) OU számítógépei helyének egy lekérdezés ciklusa befejeződött." -Tag "end"
                if((Get-Date).Hour -lt 16)
                {
                    Out-Result -Text "A ciklus újraindul $($Script:config.retrytime) másodperc múlva"
                    Start-Wait -Seconds $Script:config.retrytime
                }
                else
                {
                    Out-Result -Text "A ciklus újraindul a munkaidő kezdetén"
                    Start-Wait -Tomorrow 7 -SkipWeekend
                }
                Out-Result -Text "`nA folyamat folytatódik"
            }
        } while ($templist.Count -ne 0) # Ha a $templist tömbben nem marad elem, a ciklus befejezhető

        Out-Result -Text "A(z) $($Script:config.ounev) OU számítógépeinek helyének lekérdezése sikeresen befejeződött" -Tag "end"
        Show-Menu -BackOne -Exit
    }
    else
    {
        Out-Result -Text "Nem sikerült használható adatot szerezni a(z) $($Script:config.ounev) OU gépeiről! Folyamat vége!" -Level "err" -Tag "err"
        Show-Menu -BackOne -Exit
    }
}

# Működik (nem szép, de egyelőre megteszi)
function Get-IPrangeDevicesLocation
{
    Show-Cimsor "MEGADOTT IP TARTOMÁNY ESZKÖZEI HELYÉNEK LEKÉRDEZÉSE"
    Set-Logname "EszkozHely"
    $local = [Local]::New()
    $ipcim = Import-IPaddresses
    $ipdarab = $ipcim.Length
    $tartomany = "$($ipcim[0].ToString())-$($ipcim[-1].ToString())"
    $csv = [CSV]::New("EszközHely", "$($tartomany)_$([Time]::FileDate())")
    Show-Cimsor "A(z) $tartomany IP TARTOMÁNY ESZKÖZEI HELYÉNEK LEKÉRDEZÉSE"
    Add-Log -Text "A(z) $tartomany IP tartomány eszközei helyének lekérdezése megkezdődött:" -Tag "begin"
    [Telnet]::Login()

    # Itt kezdődik a függvény munkaciklusa. Ezen belül történik a lekérdezést végző függvény meghívása
    # és az adatok CSV fájlból való beolvasása (utóbbi akkor is, ha eleve CSV-ből vesszük az adatokat,
    # és akkor is, ha a program a saját maga által, egy korábbi ciklusban készített fájlokat használja)
    $eszkoz = New-Object System.Collections.ArrayList($null)
    for ($i = 0; $i -lt $ipdarab; $i++)
    {
        $sorszam = $i + 1
        $eszkoz.Add([Eszkoz]::New($ipcim[$i])) > $null
        $allapot = "($sorszam/$ipdarab)"
        Write-Host "$allapot A(z) $($eszkoz[$i].IPaddress) eszköz lekérdezése folyamatban." -NoNewline

        if ($eszkoz[$i].IPaddress -eq $local.IPaddress)
        {
            $sajateszkoz = $i
        }

        $remote = [Remote]::New($ipcim[$i])
        if($remote.Elerheto())
        {
            $keresesiparancs = Format-TracertCommand -Local $local -Remote $remote
            if($keresesiparancs)
            {
                $eszkoz.Lekerdez($keresesiparancs, $local, $remote, $allapot)
                if($eszkoz.Lekerdezes)
                {
                    $csv.Sync($eszkoz[$i], "IPaddress")
                    Write-Host "`rA(z) $($eszkoz[$i].IPaddress) eszköz megtalálva a(z) $($eszkoz[$i].SwitchNev) switch $($eszkoz[$i].Port) portján"
                    if ($sajateszkoz)
                    {
                        Out-LocalToUse $eszkoz[$sajateszkoz] $local $csv
                        $sajateszkoz = $false
                    }
                }
            }
        }
    }

    Out-Result -Text "A(z) $tartomany IP tartomány eszközei helyének lekérdezése sikeresen befejeződött:" -Tag "end"
    Write-Host "A program egy billetnyű leütését követően visszatér a főmenübe."
    Get-Valasztas
}

######### ELLENŐRIZVE, KÉSZ !!!!!!!!!!!!!!!!!!!!!!!!!
function Test-ADcomputersState
{
    ###############################################################
    #
    # Leírás:       Egy komplett OU eszközeit végigpingelő függvény. Az eredményt a Global beállításoknak
    #               megfelelően menti egy CSV fájlba.
    #               
    # Bemenet:      Nincs
    #
    # Kimenet:      Online, offline, vagy mindkét állapotú gépeket tartalmazó CSV fájl
    #
    # Függőségek:   * Show-Cimsor
    #               * Set-Logname
    #               * Import-ADObjects
    #               * Out-Result
    #               * Add-Log
    #               * Get-Valasztas
    #               * CSV osztály (egyelőre?)
    #               * Time osztály
    #               * PingDevice osztály
    #
    ###############################################################

    Show-Cimsor "ACTIVE DIRECTORY OU PILLANATNYI ÁLLAPOTÁNAK LEKÉRDEZÉSE"
    Set-Logname -Filename "EszkozAllapot"

    $ou = Select-OU -Computers
    $ADgeplista = Import-ADObjects -OrganizationalUnit $ou -ObjType Computers -Aktiv $Script:config.aktivnapok
    $csv = [CSV]::New("AD_GépÁllapot", "$($Script:config.ounev)_$([Time]::FileDate())")
    Show-Cimsor "A(z) $($Script:config.ounev) OU GÉPEINEK LEKÉRDEZÉSE"
    $jelenelem = 1
    $ossz = $ADgeplista.Length

    if($ADgeplista)
    {
        foreach ($gep in $ADgeplista)
        {
            $pingdev = [PingDevice]::New($gep.Name)
            Write-Host "($jelenelem/$($ossz)) A(z) $($pingdev.EszközNév) kapcsolatának ellenőrzése" -NoNewline
            if($pingdev.Online($pingdev.EszközNév))
            {
                $pingdev.IpByName()
            }

            $jelenelem++
            Out-Result -Text "A(z) $($pingdev.Eszköznév) állapota: $($pingdev.Állapot)" -Tag "devstate" -Overwrite
            $pingdev.OutCSV($csv.kimenet)
        }
        Out-Result -Text "A(z) $($Script:config.ounev) OU gépeinek lekérdezése befejeződött. Egy billentyű leütésével visszatérhetsz a főmenübe"
    }
    else
    {
        Out-Result -Text "A(z) $($Script:config.ounev) OU gépeinek lekérdezése hibába ütközött!" -Level "err" -Tag "err"
    }
    Show-Menu -BackOne -Exit
}

######### ELLENŐRIZVE, KÉSZ !!!!!!!!!!!!!!!!!!!!!!!!!
function Test-IPRangeState
{
    ###############################################################
    #
    # Leírás:       Egy komplett IP tartományt végigpingelő függvény. Az eredményt a Global beállításoknak
    #               megfelelően menti egy CSV fájlba.
    #               
    # Bemenet:      Nincs
    #
    # Kimenet:      Online, offline, vagy mindkét állapotú gépeket tartalmazó CSV fájl
    #
    # Függőségek:   * Show-Cimsor
    #               * Set-Logname
    #               * CSV osztály (egyelőre?)
    #               * Time osztály
    #               * Import osztály
    #               * IPcim osztály
    #               * PingDevice osztály
    #               * Out-Result
    #               * Add-Log
    #               * Show-Menu
    #
    ###############################################################

    Show-Cimsor "IP TARTOMÁNY LEKÉRDEZÉSE"
    Set-Logname -Filename "EszkozAllapot"
    $eszkozok = Import-IPaddresses # Importáljuk a nyers IP címeket tartalmazó tömböt

    $csv = [CSV]::New("IP_Címlista", "$($eszkozok[0].ToString())-$($eszkozok[-1].ToString())_$([Time]::FileDate())")
    Show-Cimsor "A(z) $($eszkozok[0].ToString()) - $($eszkozok[-1].ToString()) IP TARTOMÁNY LEKÉRDEZÉSE"

    $jelenelem = 1
    foreach ($eszkoz in $eszkozok)
    {
        $pingdev = [PingDevice]::New($eszkoz) # Új [PingDevice] objektum létrehozása
        Out-Result "($jelenelem/$($eszkozok.Count)) A(z) $($eszkoz) kapcsolatának ellenőrzése " -NoNewline
        if($pingdev.Online($eszkoz)) # Az eszköz online állapotát a [PingDevice] objektum végzi önmagán
        {
            $pingdev.NameByIP() # Kísérlet a név begyüjtésére az IP cím alapján
        }
        $jelenelem++
        Out-Result -Text "$($eszkoz): Állapota: $($pingdev.Állapot)$($pingdev.Nevkiir())" -Tag "devstate" -Overwrite
        $pingdev.OutCSV($csv.kimenet) # Eredmény CSV fájlba írása
    }
    Write-Host "A(z) $($eszkozok[0].ToString()) - $($eszkozok[-1].ToString()) IP tartomány lekérdezése befejeződött."
    Show-Menu -BackOne -Exit
}

######### ELLENŐRIZVE, KÉSZ !!!!!!!!!!!!!!!!!!!!!!!!!
function Get-UserCurrentComputer
{
    ###############################################################
    #
    # Leírás:       Egy felhasználó jelenlegi bejelentkezési helyét/helyeit megállapító függvény.
    #               A megadott felhasználónevet kikeresi a fileserver aktív session-jei között,
    #               és visszaadja válaszként a gép, vagy gépek nevét.
    #               
    # Bemenet:      Nincs
    #
    # Kimenet:      A felhasználó bejelentkezési helyének kiírása a konzolra
    #
    # Függőségek:   * Out-Result
    #               * Add-Log
    #               * Get-Valasztas
    #               * Get-Megjelenonev
    #               * Get-Gepnev
    #
    ###############################################################

    Show-Cimsor -Almenu "Bejelentkezésihely azonosító"

    try # Kísérlet a fileszerver automatikus megállapítására
    {
        $fileserver = ((Get-SmbConnection | Where-Object { $_.ServerName -match "File"}).ServerName)[0]
    }
    catch
    {
        $fileserver = $Script:config.fileserver
    }
    
    Write-Host 
    do
    {
        Write-Host "Add meg a lekérdezni kívánt felhasználó nevét!"
        do
        {
            $felhasznalo = Read-Host -Prompt "Felhasználónév"
            if($felhasznalo)
            {
                $conf = $true
            }
            else
            {
                Out-Result -Text "Nem adtál meg felhasználónevet! Tényleg az összes bejelentkezett felhasználó bejelentkezési gépét szeretnéd lekérdezni?" -Level "warn"
                $conf = Get-Valasztas -YesNo
            }
        } while (!$conf)
        do
        {
            if(!$Script:runtime.cred -or $hiba) # Ha még nincs $cred objektum, vagy már létezik, de a ciklus hibába futott korábban
            {
                Write-Host "Add meg a szerveradmin felhasználóneved, és jelszavadat!"
                $Script:runtime.cred = Get-LoginCred
            }
            try # A bejelentkezési sessionöket lekérdező parancs try-catch blokkja
            {
                $job = Invoke-Command -ComputerName $fileserver -Credential $cred -ArgumentList $felhasznalo -ScriptBlock { Param ($felhasznalo) Get-SmbSession | where-object { $_.ClientUserName -match $felhasznalo } } -AsJob
                $eredmenyek = Show-JobInProgress -Job $job -Text "A $felhasznalo user bejelentkezési helyének lekérése folyamatban"
                $hiba = $false
            }
            catch [System.Management.Automation.Remoting.PSRemotingTransportException]
            {
                $hiba = $true
                Out-Result -Text "Hibás felhasználónév, vagy jelszó! Add meg újra a bejelentkezési adataidat!" -Level "err"
                Add-Log -Text "Hibás felhasználónév, vagy jelszó. A fájlrendszerre való bejelentkezés sikertelen" -Tag "loginerr"
            }
        } while ($hiba)

        if($eredmenyek.Length -eq 0)
        {
            Out-Result -Text "A megadott felhasználónév, vagy felhasználónév töredék jelenleg nincs a fájlszerverhez csatlakozva" -Tag "searcherr" -Level "warn"
        }
        else
        {
            foreach($eredmeny in $eredmenyek) # Ha a felhasználó több gépen is rendelkezik aktív sessionnel, mind kiírjuk
            {
                $felhasznalo = Get-MegjelenoNev $eredmeny.ClientUserName # A kapott eredmény alapján lekérjük a megjelenő nevet
                $gepnev = Get-GepNev $eredmeny.ClientComputerName # A kapott eredmény alapján lekérjük a gép nevét
                Out-Result -Text "A(z) $felhasznalo felhasználó jelenleg a(z) $gepnev gépről van bejelentkezve" -Tag "founduser" -Level "green"
            }
        }
        Write-Host "Szeretnél másik felhasználót lekérdezni?"
        $kilep = Get-Valasztas -YesNo
    } while ($kilep)
}

function Enter-SwitchBatchMode
{
    ###############################################################
    #
    # Leírás:       Switchek listáján csoportos műveleteket elvégző függvény.
    #               
    # Bemenet:      CSV fájl
    #
    # Kimenet:      A meghívott alfüggvénytől függ
    #
    # Függőségek:   * SwitchDev Osztály
    #               * MenuElem Osztály
    #               * Telnet osztály
    #               * Show-Menu
    #               * Out-Result
    #               * Show-Cimsor
    #               * Set-Logname
    #
    # Megjegyzés:   Megírás alatt, teszteletlen
    #
    ###############################################################

    function Save-Configs
    {
        ###############################################################
        #
        # Leírás:       A switchek konfigurációjának mentését elvégző függvény. Ezt hívja meg a fő függvény,
        #               hogy elvégezze a mentést
        #               
        # Bemenet:      A fő függvénnyel megegyező
        #
        # Kimenet:      A switchek konfigurációs fájljai a TFTP szerver mappájában
        #
        # Függőségek:   * A fő függvénnyel megegyező
        #
        ###############################################################

        Out-Result -Text "A(z) $($Script:config.switch) konfigurációjának mentése folyamatban"
        $copy = "copy run tftp://$($Script:config.tftp)/$($Script:config.switch)-$([Time]::FileDate()).conf"
        [String[]]$mentes = @($copy, "", "") # Két Entert is a parancs végére kell másolni, hogy a mentési kérdést leokézzuk.
        Show-Debug $mentes
        #$result = [Telnet]::InvokeCommands($mentes)
        Show-Debug $result
    }

    function Set-AutoBackup
    {
        ###############################################################
        #
        # Leírás:       A switcheken az automatikus mentést beállító függvény
        #               
        # Bemenet:      -AsCron:    Kapcsoló, ezt beállítva a mentés időzítése is megtörténik
        #
        # Kimenet:      Nincs
        #
        # Függőségek:   * A fő függvénnyel megegyező
        #
        ###############################################################

        param([Switch]$AsCron)
        Out-Result -Text "A(z) $($Script:config.switch) automatikus mentésének beállítása folyamatban"
        $path = "path tftp://$($Script:config.tftp)/$($Script:config.switch)-`$t"
        [String[]]$setupautosave = @("conf term", "archive", $path, "write-memory", "end", "write")
        $result = [Telnet]::InvokeCommands($setupautosave)
        Show-Debug $result
        if($AsCron)
        {
            [String[]]$setupbackup = @("conf term", "kron policy-list Auto_Backup", "cli write memory", "exit", "kron occurrence Auto_Backup at 22:00 fri recurring", "end", "write")
            $result = [Telnet]::InvokeCommands($setupbackup)
            Show-Debug $result
        }
    }

    function Get-VlanAssignment
    {
        ###############################################################
        #
        # Leírás:       A switcheken VLAN kiosztását táblázatba mentő függvény
        #               
        # Bemenet:      A fő függvénnyel megegyező
        #
        # Kimenet:      A VLAN kiosztás CSV fájlban
        #
        # Függőségek:   * A fő függvénnyel megegyező
        #
        ###############################################################

        Out-Result -Text "A(z) $($Script:config.switch) VLAN kiosztásának mentésének folyamatban"
        [String[]]$vlans = @("sh vlan")
        $result = [Telnet]::InvokeCommands($vlans)
        Show-Debug $result
        # result feldolgozós rész, megírásra vár
    }

    do
    {
    ### Menü rész
        Show-Cimsor "Parancsok csoportos futtatása switcheken"
        Set-Logname -Filename "switchbatch"
        $menuList = New-Object System.Collections.ArrayList($null)
        [void]$menuList.Add([MenuElem]::New("Switchek konfigurációjának mentése"))
        [void]$menuList.Add([MenuElem]::New("Switchek automatikus mentésének beállítása"))
        [void]$menuList.Add([MenuElem]::New("Port VLAN kiosztás mentése"))
        $valaszt = Show-Menu $menuList -Exit -BackOne -JustShow

    ### Munka rész
        $switchList = Import-FromCSV "SwitchDev"
        #[Telnet]::Login()
        foreach ($switch in $switchList)
        {
            Write-Host 
            [Telnet]::SetSwitch($switch.IPaddress)
            switch ($valaszt)
            {
                1 { Save-Configs }
                2 { Set-AutoBackup }
                3 { Get-VlanAssignment }
                "V" { Break }
                Default { Out-Result -Text "Rossz függvény lett meghívva!" -Level "err" }
            }
        }
    } while ($valaszt -ne "V")
}

######### ELLENŐRIZVE, KÉSZ !!!!!!!!!!!!!!!!!!!!!!!!!
function Update-Config
{
    ###############################################################
    #
    # Leírás:       A program beállításait futásidőben megváltoztató függvény.
    #
    # Bemenet:      Nincs
    #
    # Kimenet:      Nincs
    #
    # Függőségek:   * Show-Cimsor
    #               * Get-Valasztas
    #               * Get-TrueFalse (integrálva a függvénybe, mert máshol úgysem fog kelleni)
    #
    ###############################################################

    function Get-TrueFalse
    {
        param($ertek)
        if ($ertek) { Write-Host "Bekapcsolva" -ForegroundColor Green }
        else { Write-Host "Kikapcsolva" -ForegroundColor Red }
    }
    
    $valasztas = $false
    do
    {
        Show-Cimsor "Beállítások"
        Write-Host "`r(Az itt megadott beállítások csak a jelen futásra vonatkoznak, mentésre nem kerülnek)`n"

        $csvsavemode = 0
        $optlogonline = "Az eredmények nem kerülnek mentésre"
        if ($Script:config.logonline -and $Script:config.logoffline)
        {
            $optlogonline = "Az Online és Offline gépek is mentésre kerülnek"
            $csvsavemode = 1
        }
        elseif ($Script:config.logonline -and !$Script:config.logoffline)
        {
            $optlogonline = "Csak az Online gépek kerülnek mentésre"
            $csvsavemode = 2
        }
        elseif (!$Script:config.logonline -and $Script:config.logoffline)
        {
            $optlogonline = "Csak az Offline gépek kerülnek mentésre"
            $csvsavemode = 3
        }

        if ($Script:config.method -eq 2)
        {
            $optmethod = "Sokkal lassabb, de valamivel megbízhatóbb"
        }
        else
        {
            $optmethod = "Gyors, de néha ad fals negatív eredményt"
        }
        Write-Host "(1) Logolás: " -NoNewline
        Get-TrueFalse $Script:config.log
        Write-Host "(2) Debug mód: " -NoNewline
        Get-TrueFalse $Script:config.debug
        Write-Host "(3) Pingelés során az online eszközök nevének gyűjtése (jelentősen lassíthatja a folyamatot): " -NoNewline
        Get-TrueFalse $Script:config.nevgyujtes
        Write-Host "(4) A pingelési folyamat során készülő CSV fájlba: $optlogonline"
        Write-Host "(5) A lekérdezés módja: $optmethod"
        Write-Host "(6) Az eszközök kereséséhez használt switch IP címe: $($Script:config.Switch)"
        Write-Host "(7) Alapértelmezett várakozási idő két switch parancs között miliszekundumban: $($Script:config.waittime)"
        Write-Host "(8) Maximális újrapróbálkozások száma sikertelen eredmény esetén: $($Script:config.maxhiba)"
        Write-Host "(9) AD lekérdezés esetén ennyi napon belül belépett gépek használata: $($Script:config.aktivnapok)"
        Write-Host "(K) Beállítások véglegesítése"
        Write-Host "A beállítások megváltoztatásához használd a mellettük látható számbillentyűket!"
        $valasztas = Get-Valasztas @("1", "2", "3", "4", "5", "6", "7", "8", "9", "K")

        switch ($valasztas)
        {
            1 { if ($Script:config.log) { $Script:config.log = $false} else { $Script:config.log = $true} }
            2 { if ($Script:config.debug) { $Script:config.debug = $false} else { $Script:config.debug = $true} }
            3 { if ($Script:config.nevgyujtes) { $Script:config.nevgyujtes = $false} else { $Script:config.nevgyujtes = $true} }
            4 { if ($csvsavemode -lt 3) { $csvsavemode++ } else { $csvsavemode = 0 } }
            5 { if ($Script:config.method -eq 1) { $Script:config.method = 2} else { $Script:config.method = 1} }
            6 { [Telnet]::SetSwitch() }
            7 { try { [int32]$Script:config.waittime = Read-Host -Prompt "Várakozási idő" } catch { Write-Host "HIBÁS ÉRTÉK" -ForegroundColor Red; Read-Host } }
            8 { try { [int32]$Script:config.maxhiba = Read-Host -Prompt "Megengedett hibaszám" } catch { Write-Host "HIBÁS ÉRTÉK" -ForegroundColor Red; Read-Host } }
            9 { try { [int32]$Script:config.aktivnapok = Read-Host -Prompt "Ennyi napon belül aktív gépek" } catch { Write-Host "HIBÁS ÉRTÉK" -ForegroundColor Red; Read-Host } }
        }

        switch ($csvsavemode)
        {
            1 { $Script:config.logonline = $true; $Script:config.logoffline = $true }
            2 { $Script:config.logonline = $true; $Script:config.logoffline = $false }
            3 { $Script:config.logonline = $false; $Script:config.logoffline = $true }
            0 { $Script:config.logonline = $false; $Script:config.logoffline = $false }
        }
    } while ($valasztas -ne "K")
}

###################################################################################################
###                                    FŐMENÜ BEJEGYZÉSEK                                       ###
###################################################################################################

$MainMenu = New-Object System.Collections.ArrayList($null)
[void]$MainMenu.Add([MenuElem]::New("Egy eszköz helyének megkeresése a hálózaton", $True, $False, ${function:Get-DeviceLocation}))
[void]$MainMenu.Add([MenuElem]::New("Egy OU minden számítógépe helyének lekérdezése, és fájlba mentése", $True, $True, ${function:Get-ADcomputersLocation}))
[void]$MainMenu.Add([MenuElem]::New("Egy IP cím tartomány minden eszköze helyének lekérdezése, és fájlba mentése", $True, $True, ${function:Get-IPrangeDevicesLocation}))
[void]$MainMenu.Add([MenuElem]::New("Egy OU gépeinek végigpingelése, és az eredmény fájlba mentése", $False, $True, ${function:Test-ADcomputersState}))
[void]$MainMenu.Add([MenuElem]::New("Egy IP cím tartomány végigpingelése, és az eredmény fájlba mentése", ${function:Test-IPRangeState}))
[void]$MainMenu.Add([MenuElem]::New("Parancsok csoportos futtatása switcheken", ${function:Enter-SwitchBatchMode}))
[void]$MainMenu.Add([MenuElem]::New("Egy felhasználó jelenleg használt gépének neve", $True, $True, ${function:Get-UserCurrentComputer}))

#-#-#-#-#-#-#-#-#-#-#-#-#-#-#-#-#-#-#-#-#-#-#-#-#-#-#-#-#-#-#-#-#-#-#-#-#-#-#-#-#-#-#-#-#-#-#-#-#-#
#-#-#                                   BELÉPÉSI PONT                                         #-#-#
#-#-#-#-#-#-#-#-#-#-#-#-#-#-#-#-#-#-#-#-#-#-#-#-#-#-#-#-#-#-#-#-#-#-#-#-#-#-#-#-#-#-#-#-#-#-#-#-#-#

Initialize-Basics -Admin

for(;;)
{
    Show-Cimsor -Almenu "Főmenü"
    Show-Menu -Menu $MainMenu -Exit -Options
}