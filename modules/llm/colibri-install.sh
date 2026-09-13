runHook preInstall
mkdir -p $out/bin $out/share/colibri

# The `coli` launcher locates the engine binary next to itself
# (HERE/colibri, HERE/glm) or under dirname(HERE)/libexec/colibri, so
# keep binary and launcher in the same directory.
cp c/colibri $out/share/colibri/colibri
ln -s ../share/colibri/colibri $out/bin/glm

cp c/coli $out/share/colibri/coli
chmod +x $out/share/colibri/coli
# Python modules imported by `coli` resolve from the launcher dir.
cp c/autotune.py c/doctor.py c/openai_server.py c/resource_plan.py c/version.py $out/share/colibri/
cp -r c/tools $out/share/colibri/tools

makeWrapper @PYTHONENV@/bin/python $out/bin/coli \
  --add-flags "$out/share/colibri/coli" \
  --set PYTHONPATH "@PYTHONENV_V2@/@SITEPACKAGES@:$out/share/colibri"
runHook postInstall
