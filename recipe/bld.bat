:: Remove read-only attributes natively on Windows
attrib -R SRC\*.* /S

:: -----------------------------------------------------------------------------
:: Generate Linker Aliases via Response File (to avoid CMD char limits)
:: We have removed all the source-code inlining and patching logic!
:: -----------------------------------------------------------------------------
echo syms = "DGEEV DSBEVX DPOTRF DTRTRS DGESV DGETRF DGETRI DGELS DGGEV DPBSV DPBTRS DGBSV DGBTRS DGETRS DTRSV DGEMV DTRSM DGEMM DGER DSAUPD DSEUPD SDMUC PML_2D PML_3D STEEL STEELDR COMPR14 TENSI14 MYGENMMD FILL00 RESP00 STIF00 GET00 GETCOMMON FILLCOMMON ELMT01 ELMT02 ELMT03 ELMT04 ELMT05 ELMT06 ELMT11 MATL01 MATL02 MATL03".split() > patch.py
echo aliases = [] >> patch.py
echo for s in syms: >> patch.py
echo     aliases.append("/ALTERNATENAME:" + s + "=" + s.lower() + "_") >> patch.py
echo     aliases.append("/ALTERNATENAME:" + s.lower() + "_=" + s.lower()) >> patch.py
echo with open('aliases.rsp', 'w') as f: >> patch.py
echo     f.write(' '.join(aliases) + '\n') >> patch.py

:: Execute the script to generate aliases.rsp
python patch.py
if errorlevel 1 exit 1

:: Get forward-slashed paths for CMake
set "FWD_SRC_DIR=%SRC_DIR:\=/%"
set "FWD_PREFIX=%PREFIX:\=/%"

:: Setup build directory
mkdir build
cd build

:: -----------------------------------------------------------------------------
:: Configure CMake for Ninja, Flang 21, and Release-only MSVC Run-times
:: -----------------------------------------------------------------------------
cmake -G "Ninja" ^
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
      -DCMAKE_Fortran_FLAGS="-std=legacy" ^
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
:: Move the Python extension to the site-packages directory and rename to .pyd
copy "%LIBRARY_BIN%\opensees.so" "%SP_DIR%\opensees.pyd"
if errorlevel 1 exit 1