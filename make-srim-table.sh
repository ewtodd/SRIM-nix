# make-srim-table — headless SRIM SR-Module driver.
#
# Generates a SRIM stopping-power table (.srim) for one ion in one gas at a
# given pressure/temperature, with no GUI and no committed SRModule.exe: the
# SR Module ships inside the declaratively-fetched SRIM-2013 install and runs
# under the same win32 wine prefix as the SRIM GUI package.
#
# Usage:
#   make-srim-table --ion 87Rb --gas 4He --pressure 550 --temp 293 --out FILE
#
# Args:
#   --ion AEl    ion in "AEl" notation, e.g. 87Rb (A=87, El=Rb)
#   --gas NAME   fill gas: 4He | 3He | Ar | CF4 | CH4 | P10 | iC4H10
#   --pressure   gas pressure [Torr]
#   --temp       gas temperature [K]   (default 293)
#   --out FILE   output .srim path (parent dirs created)
#   --mass U     override ion mass [u]  (default: mass number A)
#   --force      regenerate even if --out already exists
#
# Requires on PATH: wine, cabextract (wired up by the nix wrapper). The SRIM
# installer store path is passed in via $SRIM_INSTALLER.
set -euo pipefail

ION="" ; GAS="" ; PRESSURE="" ; TEMP="293" ; OUT="" ; MASS="" ; FORCE=0
while [ $# -gt 0 ]; do
  case "$1" in
    --ion)      ION="$2"; shift 2 ;;
    --gas)      GAS="$2"; shift 2 ;;
    --pressure) PRESSURE="$2"; shift 2 ;;
    --temp)     TEMP="$2"; shift 2 ;;
    --out)      OUT="$2"; shift 2 ;;
    --mass)     MASS="$2"; shift 2 ;;
    --force)    FORCE=1; shift ;;
    -h|--help)  sed -n '1,30p' "$0"; exit 0 ;;
    *) echo "make-srim-table: unknown argument '$1'" >&2; exit 2 ;;
  esac
done
for v in ION GAS PRESSURE OUT; do
  if [ -z "${!v}" ]; then echo "make-srim-table: missing --${v,,}" >&2; exit 2; fi
done

if [ -e "$OUT" ] && [ "$FORCE" -eq 0 ]; then
  echo "make-srim-table: $OUT already exists (use --force to regenerate)"; exit 0
fi

# --- ion: split "87Rb" -> A=87, symbol=Rb -> Z ---------------------------------
if [[ "$ION" =~ ^([0-9]+)([A-Za-z]+)$ ]]; then
  A="${BASH_REMATCH[1]}"; SYM="${BASH_REMATCH[2]}"
else
  echo "make-srim-table: --ion '$ION' not in 'AEl' form (e.g. 87Rb)" >&2; exit 2
fi
# index in this list == Z (slot 0 is a placeholder so Rb lands on 37)
SYMS=(n H He Li Be B C N O F Ne Na Mg Al Si P S Cl Ar K Ca Sc Ti V Cr Mn Fe Co \
      Ni Cu Zn Ga Ge As Se Br Kr Rb Sr Y Zr Nb Mo Tc Ru Rh Pd Ag Cd In Sn Sb Te \
      I Xe Cs Ba La Ce Pr Nd Pm Sm Eu Gd Tb Dy Ho Er Tm Yb Lu Hf Ta W Re Os Ir \
      Pt Au Hg Tl Pb Bi Po At Rn Fr Ra Ac Th Pa U Np Pu Am Cm Bk Cf Es Fm Md No \
      Lr Rf Db Sg Bh Hs Mt Ds Rg Cn Nh Fl Mc Lv Ts Og)
Z=-1
for i in "${!SYMS[@]}"; do
  if [ "${SYMS[$i]}" = "$SYM" ]; then Z="$i"; break; fi
done
if [ "$Z" -lt 1 ]; then echo "make-srim-table: unknown element '$SYM'" >&2; exit 2; fi
[ -n "$MASS" ] || MASS="$A"   # mass number is a sub-0.1% proxy for the ion mass

# --- gas: composition + molar mass (matched to the legacy SR-Module tables) ----
# Each entry: molar mass (g/mol), compound-correction, and one SR.IN
# "Target Elements" line per element ("Z  Name  Stoich  Mass").
GAS_M="" ; GAS_CC="1" ; GAS_ELEMS=()
case "$GAS" in
  4He|He|helium)
    GAS_M=4.003;   GAS_ELEMS=('2   "Helium"                 1             4.003') ;;
  3He)
    GAS_M=3.016;   GAS_ELEMS=('2   "Helium"                 1             3.016') ;;
  Ar|40Ar|argon)
    GAS_M=39.948;  GAS_ELEMS=('18   "Argon"                 1             39.9481') ;;
  CF4)
    GAS_M=88.0043; GAS_CC=".9585996"
    GAS_ELEMS=('6   "Carbon"                 1             12.011'
               '9   "Fluorine"               4             18.998') ;;
  CH4|methane)
    GAS_M=16.04;   GAS_CC="1.004811"
    GAS_ELEMS=('1   "Hydrogen"               4             1.008'
               '6   "Carbon"                 1             12.011') ;;
  P10)
    # 90% Ar + 10% CH4 by volume (mole fraction == volume fraction, ideal gas)
    GAS_M=$(awk 'BEGIN{printf "%.5g", 0.9*39.948 + 0.1*16.04}')
    GAS_ELEMS=('18   "Argon"                  9             39.9481'
               '6    "Carbon"                 1             12.011'
               '1    "Hydrogen"               4             1.008') ;;
  iC4H10|isobutane)
    GAS_M=$(awk 'BEGIN{printf "%.5g", 4*12.011 + 10*1.008}')
    GAS_ELEMS=('6   "Carbon"                 4             12.011'
               '1   "Hydrogen"               10            1.008') ;;
  *) echo "make-srim-table: unsupported gas '$GAS' (4He,3He,Ar,CF4,CH4,P10,iC4H10)" >&2; exit 2 ;;
esac
NUMELEM=${#GAS_ELEMS[@]}

# ideal gas: rho = P*M/(R*T), R = 62363.59 cm^3*Torr/(K*mol)  -> g/cm^3
DENSITY=$(awk -v p="$PRESSURE" -v m="$GAS_M" -v t="$TEMP" \
  'BEGIN{printf "%.8g", p*m/(62363.59*t)}')
EMAX_KEV=$(awk -v a="$MASS" 'BEGIN{printf "%.0f", 100000.0*a}')  # E-max grid [keV]

# --- locate the SR Module inside the shared win32 wine prefix -------------------
export WINEARCH=win32
export WINEPREFIX="${WINEPREFIX:-$HOME/.wine-nix/SRIM}"
export WINEDEBUG="${WINEDEBUG:--all}"
SRMOD="$WINEPREFIX/drive_c/SRIM/SR Module"

if [ ! -f "$SRMOD/SRModule.exe" ]; then
  echo "make-srim-table: SR Module not found; installing SRIM into $WINEPREFIX ..."
  if [ -z "${SRIM_INSTALLER:-}" ]; then
    echo "make-srim-table: \$SRIM_INSTALLER unset (nix wrapper should set it)" >&2; exit 1
  fi
  wineboot -i >/dev/null 2>&1 || true
  wineserver -w || true
  ( cd "$WINEPREFIX/drive_c" && mkdir -p SRIM && cd SRIM \
    && cp "$SRIM_INSTALLER" ./SRIM-2013-Std.e && chmod +w ./SRIM-2013-Std.e \
    && wine ./SRIM-2013-Std.e >/dev/null 2>&1 || true )
  sleep 3
  if [ -d "$WINEPREFIX/drive_c/SRIM/SRIM-2013-Std" ]; then
    ( cd "$WINEPREFIX/drive_c/SRIM" && mv SRIM-2013-Std/* . && rmdir SRIM-2013-Std )
  fi
  if [ -f "$WINEPREFIX/drive_c/SRIM/SRIM-Setup/MSVBvm50.exe" ]; then
    wine "$WINEPREFIX/drive_c/SRIM/SRIM-Setup/MSVBvm50.exe" >/dev/null 2>&1 || true
    sleep 2
  fi
  for ocx in "$WINEPREFIX"/drive_c/SRIM/SRIM-Setup/*.ocx; do
    [ -f "$ocx" ] && wine regsvr32 /s "$ocx" >/dev/null 2>&1 || true
  done
fi
if [ ! -f "$SRMOD/SRModule.exe" ]; then
  echo "make-srim-table: SRModule.exe still missing after install attempt" >&2; exit 1
fi

# --- write SR.IN (DOS CRLF) and run SRModule -----------------------------------
mkdir -p "$(dirname "$OUT")"
OUT_ABS="$(cd "$(dirname "$OUT")" && pwd)/$(basename "$OUT")"

{
  printf -- '---Stopping/Range Input Data (Number-format: Period = Decimal Point)\r\n'
  printf -- '---Output File Name\r\n'
  printf -- '"%s"\r\n' "$OUT_ABS"
  printf -- '---Ion(Z), Ion Mass(u)\r\n'
  printf -- '%s   %s\r\n' "$Z" "$MASS"
  printf -- '---Target Data: (Solid=0,Gas=1), Density(g/cm3), Compound Corr.\r\n'
  printf -- '1    %s    %s\r\n' "$DENSITY" "$GAS_CC"
  printf -- '---Number of Target Elements\r\n'
  printf -- ' %s\r\n' "$NUMELEM"
  printf -- '---Target Elements: (Z), Target name, Stoich, Target Mass(u)\r\n'
  for e in "${GAS_ELEMS[@]}"; do printf -- '%s\r\n' "$e"; done
  printf -- '---Output Stopping Units (1-8)\r\n'
  printf -- ' 3\r\n'
  printf -- '---Ion Energy : E-Min(keV), E-Max(keV)\r\n'
  printf -- ' 0.5    %s\r\n' "$EMAX_KEV"
} > "$SRMOD/SR.IN"

rm -f "$OUT_ABS"
( cd "$SRMOD" && wine SRModule.exe >/dev/null 2>&1 ) || true
wineserver -w 2>/dev/null || true

if [ ! -s "$OUT_ABS" ]; then
  echo "make-srim-table: SRModule produced no output for $ION in $GAS" >&2
  exit 1
fi
echo "make-srim-table: wrote $OUT_ABS  (Z=$Z A=$A gas=$GAS rho=$DENSITY g/cm^3)"
