# Prepara este PC con Windows para producir contenido de Apruébalo en C:\Apruebalo\contenido.
#
# Uso: deja kit-plantillas-apruebalo.zip en Descargas, abre PowerShell donde está este archivo y ejecuta
#   powershell -ExecutionPolicy Bypass -File .\preparar-pc.ps1
#
# Pasos: 1) carpetas, 2) descomprime el kit, 3) instala Python 3, Node.js y Playwright con Chromium
# y hace el render de prueba, 4) copia las reglas de marca para Claude Code, 5) agrega el MCP de Notion.

$ErrorActionPreference = 'Stop'
$Raiz = 'C:\Apruebalo\contenido'

function Paso($texto) { Write-Host "`n== $texto" -ForegroundColor Cyan }

function Actualizar-Path {
    $env:Path = [Environment]::GetEnvironmentVariable('Path', 'Machine') + ';' +
                [Environment]::GetEnvironmentVariable('Path', 'User')
}

function Instalar-ConWinget($id) {
    winget install --id $id --exact --silent --accept-source-agreements --accept-package-agreements
    if ($LASTEXITCODE -ne 0) { Write-Host "winget terminó con código $LASTEXITCODE para $id" -ForegroundColor Yellow }
    Actualizar-Path
}

function Carpeta-Descargas {
    try {
        $ruta = (New-Object -ComObject Shell.Application).NameSpace('shell:Downloads').Self.Path
        if ($ruta -and (Test-Path $ruta)) { return $ruta }
    } catch { }
    return Join-Path $env:USERPROFILE 'Downloads'
}

# Devuelve la ruta de python.exe, sin confundirlo con el acceso directo de Microsoft Store.
function Ruta-Python {
    if (Get-Command py -ErrorAction SilentlyContinue) {
        try {
            $ruta = & py -3 -c "import sys; print(sys.executable)" 2>$null
            if ($LASTEXITCODE -eq 0 -and $ruta) { return "$ruta".Trim() }
        } catch { }
    }
    $python = Get-Command python -ErrorAction SilentlyContinue
    if ($python -and $python.Source -notlike '*\WindowsApps\*') { return $python.Source }
    $encontrado = Get-ChildItem "$env:LOCALAPPDATA\Programs\Python\Python3*\python.exe", "$env:ProgramFiles\Python3*\python.exe" -ErrorAction SilentlyContinue |
        Select-Object -Last 1
    if ($encontrado) { return $encontrado.FullName }
    return $null
}

Paso '1/5 Carpetas'
foreach ($carpeta in 'kit', 'capturas\originales', 'capturas\listas', 'salida') {
    New-Item -ItemType Directory -Force -Path (Join-Path $Raiz $carpeta) | Out-Null
}

Paso '2/5 Kit'
$Zip = Join-Path (Carpeta-Descargas) 'kit-plantillas-apruebalo.zip'
if (-not (Test-Path $Zip)) { throw "No encuentro $Zip" }
Expand-Archive -Path $Zip -DestinationPath (Join-Path $Raiz 'kit') -Force
if (-not (Test-Path "$Raiz\kit\README.md") -or -not (Test-Path "$Raiz\kit\render.py")) {
    throw 'El zip no dejó kit\README.md y kit\render.py: revisa su contenido'
}

Paso '3/5 Python, Node.js y Playwright'
if (-not (Get-Command winget -ErrorAction SilentlyContinue)) {
    throw 'Falta winget: instala "Instalador de aplicación" desde Microsoft Store y vuelve a ejecutar'
}
if (-not (Ruta-Python)) { Instalar-ConWinget 'Python.Python.3.13' }
$Py = Ruta-Python
if (-not $Py) { throw 'Python no quedó disponible: cierra PowerShell, ábrelo de nuevo y vuelve a ejecutar' }
if (-not (Get-Command node -ErrorAction SilentlyContinue)) { Instalar-ConWinget 'OpenJS.NodeJS.LTS' }

& $Py -m pip install --upgrade playwright
if ($LASTEXITCODE -ne 0) { throw 'Falló pip install playwright' }
& $Py -m playwright install chromium
if ($LASTEXITCODE -ne 0) { throw 'Falló la instalación de Chromium para Playwright' }

# Render de prueba: debe dejar 11 PNG en salida\ejemplo y terminar con «0 con avisos» (código 0).
Push-Location $Raiz
& $Py kit\render.py
$CodigoRender = $LASTEXITCODE
Pop-Location
$Png = @(Get-ChildItem "$Raiz\salida\ejemplo\*.png" -ErrorAction SilentlyContinue).Count

Paso '4/5 Reglas de marca para Claude Code'
# La skill se llama ccapb. Si existe una carpeta con un nombre anterior, se renombra. Un SKILL.md que
# ya existe no se sobrescribe con el del kit, para no perder cambios; solo se asegura la línea name.
$Skill = Join-Path $Raiz '.claude\skills\ccapb'
foreach ($NombreAntiguo in 'apruebalo', 'cctmc') {
    $SkillAntigua = Join-Path $Raiz ".claude\skills\$NombreAntiguo"
    if ((Test-Path $SkillAntigua) -and -not (Test-Path $Skill)) { Rename-Item $SkillAntigua 'ccapb' }
}
New-Item -ItemType Directory -Force -Path $Skill | Out-Null
$ArchivoSkill = Join-Path $Skill 'SKILL.md'
$Origen = if (Test-Path $ArchivoSkill) { $ArchivoSkill } else { "$Raiz\kit\SKILL.md" }
$Texto = (Get-Content $Origen -Raw -Encoding UTF8) -replace '(?m)^name:[^\r\n]*', 'name: ccapb'
[IO.File]::WriteAllText($ArchivoSkill, $Texto)

Paso '5/5 Notion'
$Claude = Get-Command claude -ErrorAction SilentlyContinue
if ($Claude) {
    Push-Location $Raiz
    & claude mcp add --transport http notion https://mcp.notion.com/mcp
    Pop-Location
    $Notion = 'agregado a Claude Code; falta autorizarlo (ver abajo)'
} else {
    $Notion = 'pendiente: no encontré Claude Code (comando claude) en este PC'
}

Paso 'Resumen'
$Node = if (Get-Command node -ErrorAction SilentlyContinue) { & node --version } else { 'no encontrado' }
Write-Host "Python:     $(& $Py --version)"
Write-Host "Node.js:    $Node"
Write-Host "Playwright: $(& $Py -m playwright --version)"
if ($Png -eq 11 -and $CodigoRender -eq 0) {
    Write-Host "Render:     OK, 11 PNG sin avisos en $Raiz\salida\ejemplo" -ForegroundColor Green
} else {
    Write-Host "Render:     REVISAR, $Png de 11 PNG y render.py terminó con código $CodigoRender" -ForegroundColor Red
}
Write-Host "Skill:      $Skill\SKILL.md"
Write-Host "Notion:     $Notion"
if ($Claude) {
    Write-Host "`nPara autorizar Notion: en $Raiz ejecuta claude, escribe /mcp, elige notion y luego Authenticate; se abrirá el navegador."
}
Read-Host "`nPresiona Enter para cerrar"
