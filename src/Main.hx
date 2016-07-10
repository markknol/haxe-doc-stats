package;

import Xml;
import haxe.ds.StringMap;
import haxe.rtti.CType.MetaData;
import haxe.rtti.CType.TypeInfos;
import haxe.rtti.CType.TypeTree;
import haxe.rtti.XmlParser;
import sys.FileSystem;
import sys.io.File;
import templo.Template;
using StringTools;

/**
 * @author Mark Knol
 */
class Main {
  public static function main(){
    var args = Sys.args();
    if (args.length == 0) {
      Sys.println("run with 'DocStats.n arg0 arg1 arg2 arg3' \n" +
        "\t[arg0] path to xml directory. default: 'xml/' \n" +
        "\t[arg1] path to output file. default: 'xml/index.html' \n" +
        "\t[arg2] path to template html-file. default: 'layout.html' \n" +
        "\t[arg3] path to log-file. default: 'xml/log.txt' \n");
        return;
    }
    
    inline function getArg(i, fallback) return args[i] == null ? fallback : args[i];
    
    var directory = getArg(0, "xml/");
    if (!directory.endsWith("/")) directory += "/";
    
    var outputPath = getArg(1, directory + "index.html");
    var templatePath = getArg(2, "layout.html");
    
    new StatsBuilder(directory, outputPath, templatePath);
  }
}
