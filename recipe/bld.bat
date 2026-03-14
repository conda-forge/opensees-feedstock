:: Remove read-only attributes natively on Windows
attrib -R SRC\*.* /S

:: Safely patch Fortran files: Scrub implicit none, fix sequence, and INLINE headers
echo import os, re > patch.py
echo headers = {} >> patch.py
echo for root, dirs, files in os.walk('SRC'): >> patch.py
echo     for file in files: >> patch.py
echo         if file.lower().endswith(('.h', '.inc')): >> patch.py
echo             with open(os.path.join(root, file), 'r', encoding='latin1') as f: c = f.read() >> patch.py
echo             c = re.sub(r'(?i)implicit\s*none', '             ', c) >> patch.py
echo             c = re.sub(r'(?i)implicit\s*undefined', '                  ', c) >> patch.py
echo             headers[file.lower()] = c >> patch.py
echo for root, dirs, files in os.walk('SRC'): >> patch.py
echo     for file in files: >> patch.py
echo         if not file.lower().endswith(('.f', '.f90', '.f77', '.for')): continue >> patch.py
echo         f_path = os.path.join(root, file) >> patch.py
echo         with open(f_path, 'r', encoding='latin1') as f: c = f.read() >> patch.py
echo         c_new = re.sub(r'(?i)implicit\s*none', '             ', c) >> patch.py
echo         c_new = re.sub(r'(?i)implicit\s*undefined', '                  ', c_new) >> patch.py
echo         if file.lower() == 'c14-sk-m.f': >> patch.py
echo             lines = c_new.splitlines() >> patch.py
echo             for i in range(len(lines) - 1): >> patch.py
echo                 if 'cDEC$ ATTRIBUTES' in lines[i] and 'COMMON /MLSVAL/' in lines[i+1]: >> patch.py
echo                     lines[i], lines[i+1] = lines[i+1], lines[i] >> patch.py
echo             c_new = '\n'.join(lines) + '\n' >> patch.py
echo         lines = c_new.splitlines() >> patch.py
echo         out_lines = [] >> patch.py
echo         for line in lines: >> patch.py
echo             m = re.match(r"(?i)^\s*include\s+['\x22](.*?)['\x22]", line) >> patch.py
echo             if m: >> patch.py
echo                 h_name = os.path.basename(m.group(1)).lower() >> patch.py
echo                 if h_name in headers: >> patch.py
echo                     out_lines.append(headers[h_name]) >> patch.py
echo                     continue >> patch.py
echo             out_lines.append(line) >> patch.py
echo         c_new = '\n'.join(out_lines) + '\n' >> patch.py
echo         if c != c_new: >> patch.py
echo             with open(f_path, 'w', encoding='latin1') as f: f.write(c_new) >> patch.py
echo             print('Patched and inlined', f_path) >> patch.py
:: Generate Linker Aliases via Response File (to avoid CMD char limits)
echo syms = "DGEEV DSBEVX DPOTRF DTRTRS DGESV DGETRF DGETRI DGELS DGGEV DPBSV DPBTRS DGBSV DGBTRS DGETRS DTRSV DGEMV DTRSM DGEMM DGER DSAUPD DSEUPD SDMUC PML_2D PML_3D STEEL STEELDR COMPR14 TENSI14 MYGENMMD FILL00 RESP00 STIF00 GET00 GETCOMMON FILLCOMMON ELMT01 ELMT02 ELMT03 ELMT04 ELMT05 ELMT06 ELMT11 MATL01 MATL02 MATL03".split() >> patch.py
echo aliases = [] >> patch.py
echo for s in syms: >> patch.py
echo     aliases.append("/ALTERNATENAME:" + s + "=" + s.lower() + "_") >> patch.py
echo     aliases.append("/ALTERNATENAME:" + s.lower() + "_=" + s.lower()) >> patch.py
echo with open('aliases.rsp', 'w') as f: >> patch.py
echo     f.write(' '.join(aliases) + '\n') >> patch.py

:: Execute the patch and generate aliases.rsp
python patch.py
if errorlevel 1 exit 1

:: Get forward-slashed paths for CMake
set "FWD_SRC_DIR=%SRC_DIR:\=/%"
set "FWD_PREFIX=%PREFIX:\=/%"

:: Setup build directory
mkdir build
cd build

:: Configure CMake (Now explicitly forcing Conda's Python to fix OverLinkingError)
cmake -G "NMake Makefiles JOM" ^
      -DCMAKE_INSTALL_PREFIX="%LIBRARY_PREFIX%" ^
      -DCMAKE_PREFIX_PATH="%LIBRARY_PREFIX%" ^
      -DCMAKE_BUILD_TYPE=Release ^
      -DTCL_LIBRARY="%LIBRARY_PREFIX%/lib/tcl86t.lib" ^
      -DTCL_INCLUDE_PATH="%LIBRARY_PREFIX%/include" ^
      -DPython_EXECUTABLE="%FWD_PREFIX%/python.exe" ^
      -DPython3_EXECUTABLE="%FWD_PREFIX%/python.exe" ^
      -DPython_FIND_REGISTRY=NEVER ^
      -DPython3_FIND_REGISTRY=NEVER ^
      -DOpenSees_ENABLE_MPI=OFF ^
      -DCMAKE_CXX_FLAGS="/EHsc /w -DH5_BUILT_AS_DYNAMIC_LIB" ^
      -DCMAKE_EXE_LINKER_FLAGS="@%FWD_SRC_DIR%/aliases.rsp" ^
      -DCMAKE_SHARED_LINKER_FLAGS="@%FWD_SRC_DIR%/aliases.rsp" ^
      -DCMAKE_MODULE_LINKER_FLAGS="@%FWD_SRC_DIR%/aliases.rsp" ^
      ..
if errorlevel 1 exit 1

:: Build parallel targets again for speed
cmake --build . --config Release --target OpenSees --parallel %CPU_COUNT%
if errorlevel 1 exit 1

cmake --build . --config Release --target OpenSeesPy --parallel %CPU_COUNT%
if errorlevel 1 exit 1

:: Install Step
cmake --install . --verbose
if errorlevel 1 exit 1

:: --- Post-Build Fixes ---
:: Move the Python extension to the site-packages directory and rename to .pyd
copy "%LIBRARY_BIN%\opensees.so" "%SP_DIR%\opensees.pyd"
if errorlevel 1 exit 1