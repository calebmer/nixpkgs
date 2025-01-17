{ config, lib, pkgs, ... }:

with lib;

let
  cfg = config.services.hbase;

  defaultConfig = {
    "hbase.rootdir" = "file://${cfg.dataDir}/hbase";
    "hbase.zookeeper.property.dataDir" = "${cfg.dataDir}/zookeeper";
  };

  buildProperty = configAttr:
    (builtins.concatStringsSep "\n"
      (lib.mapAttrsToList
        (name: value: ''
          <property>
            <name>${name}</name>
            <value>${builtins.toString value}</value>
          </property>
        '')
        configAttr));

  configFile = pkgs.writeText "hbase-site.xml"
    ''<configuration>
        ${buildProperty (defaultConfig // cfg.settings)}
      </configuration>
    '';

  configDir = pkgs.runCommand "hbase-config-dir" { preferLocalBuild = true; } ''
    mkdir -p $out
    cp ${cfg.package}/conf/* $out/
    rm $out/hbase-site.xml
    ln -s ${configFile} $out/hbase-site.xml
  '' ;

in {

  ###### interface

  options = {

    services.hbase = {

      enable = mkOption {
        type = types.bool;
        default = false;
        description = ''
          Whether to run HBase.
        '';
      };

      package = mkOption {
        type = types.package;
        default = pkgs.hbase;
        defaultText = literalExpression "pkgs.hbase";
        description = ''
          HBase package to use.
        '';
      };


      user = mkOption {
        type = types.str;
        default = "hbase";
        description = ''
          User account under which HBase runs.
        '';
      };

      group = mkOption {
        type = types.str;
        default = "hbase";
        description = ''
          Group account under which HBase runs.
        '';
      };

      dataDir = mkOption {
        type = types.path;
        default = "/var/lib/hbase";
        description = ''
          Specifies location of HBase database files. This location should be
          writable and readable for the user the HBase service runs as
          (hbase by default).
        '';
      };

      logDir = mkOption {
        type = types.path;
        default = "/var/log/hbase";
        description = ''
          Specifies the location of HBase log files.
        '';
      };

      settings = mkOption {
        type = with lib.types; attrsOf (oneOf [ str int bool ]);
        default = defaultConfig;
        description = ''
          configurations in hbase-site.xml, see <link xlink:href="https://github.com/apache/hbase/blob/master/hbase-server/src/test/resources/hbase-site.xml"/> for details.
        '';
      };

    };

  };

  ###### implementation

  config = mkIf config.services.hbase.enable {

    systemd.tmpfiles.rules = [
      "d '${cfg.dataDir}' - ${cfg.user} ${cfg.group} - -"
      "d '${cfg.logDir}' - ${cfg.user} ${cfg.group} - -"
    ];

    systemd.services.hbase = {
      description = "HBase Server";
      wantedBy = [ "multi-user.target" ];

      environment = {
        # JRE 15 removed option `UseConcMarkSweepGC` which is needed.
        JAVA_HOME = "${pkgs.jre8}";
        HBASE_LOG_DIR = cfg.logDir;
      };

      serviceConfig = {
        User = cfg.user;
        Group = cfg.group;
        ExecStart = "${cfg.package}/bin/hbase --config ${configDir} master start";
      };
    };

    users.users.hbase = {
      description = "HBase Server user";
      group = "hbase";
      uid = config.ids.uids.hbase;
    };

    users.groups.hbase.gid = config.ids.gids.hbase;

  };
}
