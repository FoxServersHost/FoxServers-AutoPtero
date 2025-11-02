#!/usr/bin/env bash
mkdir -p fastdl-agent panel-module systemd nginx docs
echo "#!/usr/bin/env bash" > install.sh
echo "#!/usr/bin/env bash" > update.sh
echo "#!/usr/bin/env bash" > uninstall.sh
echo "Phase 2 code inserted manually in ChatGPT" >> install.sh
echo "phase2" >> update.sh
echo "phase2" >> uninstall.sh
echo "<?php // controller" > panel-module/FastDLController.php
echo "<?php // routes" > panel-module/api-server.php
echo "<!-- vue component -->" > panel-module/FastDLTab.vue
echo '{"name": "fastdl-agent"}' > fastdl-agent/package.json
echo "// node agent" > fastdl-agent/index.js
echo "[Unit]" > systemd/fastdl-agent.service
echo "server { }" > nginx/panel.conf.tpl
echo "server { }" > nginx/wings.conf.tpl
echo "server { }" > nginx/fastdl.conf.tpl
echo "FoxServers FULL installer" > README.md
echo "Project generated." 
