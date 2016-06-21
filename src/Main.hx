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
  static var excludedField = ["haxe_doc","meta","impl"];
  static function main() {
    var args = Sys.args();
    
    var directory = args[0];
    if (!directory.endsWith("/")) directory += "/";
    
    var log = "";
    var totals = new Stats("total");
    
    inline function getTargetName(file:String) return file.replace(".xml", "");

    inline function getDoc(child:Xml):Null<String> {
      return [for(haxeDoc in child.elementsNamed("haxe_doc")) haxeDoc.firstChild().nodeValue][0];
    }
    
    var documentationByClassPath:StringMap<String> = new StringMap<String>();
    
    // fill targets with empty maps
    var targets = ["toplevel", "sys", "haxe", "js", "cpp", "lua", "java", "macro", "neko", "php", "python", "hl", "flash", "cs"];
    var stats:StringMap<Stats> = [for (target in targets) target => new Stats(target)];
    var subStats = new StringMap<Stats>();
    
    
    inline function process(typeInfos:TypeInfos, typeId:TypeId, addStats:Stats->Void = null) {
      if (typeInfos == null || typeInfos.path == null || typeInfos.isPrivate || !typeInfos.file.endsWith(".hx")) return;
      
      var classPath = typeInfos.path;
      var classPaths = classPath.split(".");
      classPaths.pop(); // remove class name
      var packageName = classPaths[0];
      
      var stat:Stats = classPaths.length == 0 ? stats.get("toplevel") : stats.get(packageName);
      if (stat == null) stats.set(packageName, stat = new Stats(packageName));
      
      inline function saveStat(stat:Stats) {
        stat.addClassDoc(typeId, typeInfos, typeInfos.doc);
        if (addStats != null) addStats(stat);
      }
      
      if (classPaths.length >= 1) {
        var subPackageName = (classPaths.length == 1) ? classPaths[0] : classPaths[0] + "." + classPaths[1];
        var subStat:Stats = subStats.get(subPackageName);
        if (subStat == null) subStats.set(subPackageName, subStat = new Stats(subPackageName, true));
        saveStat(subStat);
      }
      
      saveStat(stat);
    }
    
    function find(root:Array<TypeTree>) {
      for (el in root) {
        switch(el) {
          case TPackage(name, full, subs): 
            find(subs);
            
          case TClassdecl( c ): 
            var typeInfos:TypeInfos = c;
            process(c, TypeId.CLASS, function(stat) {
              for (field in c.fields) 
                if (field.isPublic && !field.isOverride) 
                  stat.addFieldDoc(c, field, field.doc);
                  
              for (field in c.statics) 
                if (field.isPublic && !field.isOverride) 
                  stat.addFieldDoc(c, field, field.doc);
            });
            
          case TEnumdecl( e ): 
            process(e, TypeId.ENUM, function(stat) {
              for (field in e.constructors)
                stat.addFieldDoc(e, field, field.doc);
            });
            
          case TTypedecl( t ): 
            process(t, TypeId.TYPEDEF); 
            
          case TAbstractdecl( a ):
            process(a, TypeId.ABSTRACT);
        }
      }
    }
    
    var parser = new XmlParser();
    // fill maps with data
    for (file in FileSystem.readDirectory(directory)) {
      if (file.indexOf(".xml") == -1) continue;
      var xml = Xml.parse(File.getContent(directory + file));
      var target = getTargetName(file);
      if (!stats.exists(target)) stats.set(target, new Stats(target));
      parser.process(xml.firstElement(), getTargetName(file));
    }
    
    find(parser.root);
    
    for (stat in stats) {
      log += stat.toString();
      totals.add(stat);
    }
    
    log += "-- total -- \n\n";
    log += totals.toString();
    
    //trace(log);
    
    File.saveContent(directory + "log.txt", log);
    
    var templatePath = args[1];
    if (templatePath == null) templatePath = "layout.html";
    var template = Template.fromFile(templatePath);
    File.saveContent(directory + "index.html", template.execute({
      stats: [for (stat in stats) stat],
      subStats: [for (stat in stats) stat.name => [for (s in subStats) if (s.name.startsWith(stat.name)) s]],
      totals: totals,
      title: directory.replace("/"," "),
      Math: Math,
    }));
  }
}

typedef Docs = Array<String>;

@:keep private class StatInfo {
  public var total:Int = 0;
  public var documented:Int = 0;
  
  public inline function new() {
  }
  
  public function getPercentage() {
    return toFixed(documented / total * 100.0, 2);
  }
  
  public function add(info:StatInfo) {
    total += info.total;
    documented += info.documented;
  }
  
  public function getProgressBar() {
    var percentage = getPercentage();
    return '<div class="progress"><div class="progress-bar progress-bar-${Stats.getClassName(percentage)}" style="width: ${percentage}%" aria-valuemin="0" aria-valuemax="100" role="progressbar" aria-valuenow="${Math.floor(percentage)}">${percentage}%</div></div>';
  }
  
  static inline function toFixed(value:Float, precision) {
    return Math.floor(value * Math.pow(10, precision)) / Math.pow(10, precision);
  }
}

@:keep private class Stats {
  public var name(default, null):String;
  
  public var types:StatInfo = new StatInfo();
  public var fields:StatInfo = new StatInfo();
  public var all:Array<StatInfo>;
  
  public var collectMissingTypes:Bool;
  public var missingTypes:Array<String> = [];
  public var missingFields:Array<String> = [];
  
  public inline function new(name:String, collectMissingTypes:Bool = false) {
    this.name = name;
    this.collectMissingTypes = collectMissingTypes;
    all = [types, fields];
  }
  
  public function add(stats:Stats) {
    for (i in 0...stats.all.length) {
      all[i].add(stats.all[i]);
    }
  }
  
  private function hasInvalidMetaData(el:{meta:MetaData}) {
    for (meta in el.meta) if ((meta.name == ":dox" && meta.params[0] == "hide") || meta.name == ":noCompletion") {
      return true;
    }
    return false;
  }
  
  public function addClassDoc(typeId:TypeId, type:TypeInfos, doc:String) {
    if (hasInvalidMetaData(type)) return;
    types.total++;
    if (hasDoc(doc)) {
      types.documented ++;
    } else if (collectMissingTypes) {
      missingTypes.push(type.path);
    }
  }
  
  public function addFieldDoc(type:TypeInfos, field:{meta:MetaData, name:String}, doc:String) {
    if (hasInvalidMetaData(field)) return;
    
    fields.total++;
    if (hasDoc(doc)) {
      fields.documented ++;
    } else if (collectMissingTypes) {
      missingFields.push(type.path + "." + field.name);
    }
  }
  
  inline function hasDoc(doc:String) return (doc != null && doc.length > 1);
    
  public function toString() {
    var v = "";
    var newline = "\n";
    v += (name + " types: " + types.total + " - " + types.getPercentage() + "% documented") + newline;
    v += (name + " members: " + fields.total + " - " + fields.getPercentage() + "% documented") + newline;
    v += "\n";
    return v;
  }
  
  public function getClass(percentage:Float) {
    return getClassName(percentage);
  }
  
  public static function getClassName(percentage:Float) {
    return if (percentage < 10) "important";
           else if (percentage > 75) "success";
           else "warning";
  }
  
}

@:enum abstract TypeId(Int) {
  public var CLASS = 1;
	public var ENUM = 2;
	public var TYPEDEF = 3;
	public var ABSTRACT = 4;
}
