:: Remove read-only attributes natively on Windows
attrib -R SRC\*.* /S
attrib -R OTHER\*.* /S

:: -----------------------------------------------------------------------------
:: Minimalist Patch: ONLY inline headers (No implicit none scrubbing)
:: -----------------------------------------------------------------------------
echo import os, re > patch.py
echo headers = {} >> patch.py
echo for d in ['SRC', 'OTHER']: >> patch.py
echo     for root, dirs, files in os.walk(d): >> patch.py
echo         for file in files: >> patch.py
echo             if file.lower().endswith(('.h', '.inc')): >> patch.py
echo                 with open(os.path.join(root, file), 'r', encoding='latin1') as f: headers[file.lower()] = f.read() >> patch.py
echo for d in ['SRC', 'OTHER']: >> patch.py
echo     for root, dirs, files in os.walk(d): >> patch.py
echo         for file in files: >> patch.py
echo             if not file.lower().endswith(('.f', '.f90', '.f77', '.for')): continue >> patch.py
echo             f_path = os.path.join(root, file) >> patch.py
echo             with open(f_path, 'r', encoding='latin1') as f: c = f.read() >> patch.py
echo             lines = c.splitlines() >> patch.py
echo             out_lines = [] >> patch.py
echo             for line in lines: >> patch.py
echo                 m = re.match(r"(?i)^\s*include\s+['\x22](.*?)['\x22]", line) >> patch.py
echo                 if m: >> patch.py
echo                     h_name = os.path.basename(m.group(1)).lower() >> patch.py
echo                     if h_name in headers: >> patch.py
echo                         out_lines.append(headers[h_name]) >> patch.py
echo                         continue >> patch.py
echo                 out_lines.append(line) >> patch.py
echo             c_new = '\n'.join(out_lines) + '\n' >> patch.py
echo             if c != c_new: >> patch.py
echo                 with open(f_path, 'w', encoding='latin1') as f: f.write(c_new) >> patch.py
echo                 print('Inlined headers in', f_path) >> patch.py

:: -----------------------------------------------------------------------------
:: Generate Linker Aliases via Response File
:: -----------------------------------------------------------------------------
echo syms = "DGEEV DSBEVX DPOTRF DTRTRS DGESV DGETRF DGETRI DGELS DGGEV DPBSV DPBTRS DGBSV DGBTRS DGETRS DTRSV DGEMV DTRSM DGEMM DGER DSAUPD DSEUPD SDMUC PML_2D PML_3D STEEL STEELDR COMPR14 TENSI14 MYGENMMD FILL00 RESP00 STIF00 GET00 GETCOMMON FILLCOMMON ELMT01 ELMT02 ELMT03 ELMT04 ELMT05 ELMT06 ELMT11 MATL01 MATL02 MATL03".split() >> patch.py
echo aliases = [] >> patch.py
echo for s in syms: >> patch.py
echo     aliases.append("/ALTERNATENAME:" + s + "=" + s.lower() + "_") >> patch.py
echo     aliases.append("/ALTERNATENAME:" + s.lower() + "_=" + s.lower()) >> patch.py
echo with open('aliases.rsp', 'w') as f: >> patch.py
echo     f.write(' '.join(aliases) + '\n') >> patch.py

:: Execute the minimalist patch
python patch.py
if errorlevel 1 exit 1

:: Get forward-slashed paths for CMake
set "FWD_SRC_DIR=%SRC_DIR:\=/%"
set "FWD_PREFIX=%PREFIX:\=/%"

:: Setup build directory
mkdir build
cd build

:: -----------------------------------------------------------------------------
:: Configure CMake (No -std flag, strictly relying on default permissiveness)
:: -----------------------------------------------------------------------------
cmake -G "Ninja" %CMAKE_ARGS% ^
      -DCMAKE_TRY_COMPILE_CONFIGURATION=Release ^
      -DCMAKE_MSVC_RUNTIME_LIBRARY="MultiThreadedDLL" ^
      -DCMAKE_NINJA_FORCE_RESPONSE_FILE=ON ^
      -DCMAKE_Fortran_USE_RESPONSE_FILE_FOR_OBJECTS=ON ^
      -DCMAKE_Fortran_USE_RESPONSE_FILE_FOR_INCLUDES=ON ^
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

:: Build parallel targets using Ninja
cmake --build . --config Release --target OpenSees --parallel %CPU_COUNT%
if errorlevel 1 exit 1

cmake --build . --config Release --target OpenSeesPy --parallel %CPU_COUNT%
if errorlevel 1 exit 1

:: Install Step
cmake --install . --verbose
if errorlevel 1 exit 1

:: --- Post-Build Fixes ---
copy "%LIBRARY_BIN%\opensees.so" "%SP_DIR%\opensees.pyd"
if errorlevel 1 exit 1