package;

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
class StatsBuilder{
  static inline var TOPLEVEL = "toplevel";
  static var baseTargets = [TOPLEVEL];
  
  public function new(directory:String, outputPath:String, templatePath:String) {
    
    // stats by type path. fill targets with empty maps
    var stats:StringMap<Stat> = [for (platform in baseTargets) platform => new Stat(platform)];
    
    // sub stats by type path. substats are the packages in the packages
    var subStats = new StringMap<Stat>();
    
  
    function hasValidMetaData(el:{meta:MetaData}) {
      for (meta in el.meta) if (meta.name == ":dox" || meta.name == ":noCompletion") {
        return false;
      }
      return true;
    }
  
    // process haxe type. stats can be decorated while collecting
    inline function process(typeInfos:TypeInfos, typeId:TypeId, decorator:Stat->Void = null) {
      if (typeInfos == null || typeInfos.path == null || typeInfos.isPrivate || !typeInfos.file.endsWith(".hx")) return;
      if (!hasValidMetaData(typeInfos)) return;
      
      var typePath = typeInfos.path;
      var typePaths = typePath.split(".");
      typePaths.pop(); // remove actual type name
      var packageName = typePaths[0];
      
      var stat:Stat = typePaths.length == 0 ? stats.get(TOPLEVEL) : stats.get(packageName);
      if (stat == null) stats.set(packageName, stat = new Stat(packageName));
      
      inline function processType(stat:Stat) {
        stat.addTypeInfo(typeId, typeInfos, typeInfos.doc);
        if (decorator != null) decorator(stat);
      }
      
      if (typePaths.length >= 1) {
        var subPackageName = typePaths.length == 1 ? '$packageName' : '$packageName.${typePaths[1]}';
        var subStat:Stat = subStats.get(subPackageName);
        if (subStat == null) subStats.set(subPackageName, subStat = new Stat(subPackageName, true));
        processType(subStat);
      }
      
      processType(stat);
    }
    
    // recursive collect+processes all info from TypeTrees
    function collect(types:Array<TypeTree>) {
      for (type in types) {
        switch(type) {
          case TPackage(name, full, subs): 
            collect(subs);
            
          case TClassdecl(c):
            var typeInfos:TypeInfos = c;
            process(c, TypeId.CLASS, function(stat) {
              for (field in c.fields) 
                if (field.isPublic && !field.isOverride && hasValidMetaData(field)) 
                  stat.addFieldInfo(c, field, field.doc);
                  
              for (field in c.statics) 
                if (field.isPublic && !field.isOverride && hasValidMetaData(field)) 
                  stat.addFieldInfo(c, field, field.doc);
            });
            
          case TEnumdecl(e):
            process(e, TypeId.ENUM, function(stat) {
              for (field in e.constructors)
                if (hasValidMetaData(field))
                  stat.addFieldInfo(e, field, field.doc);
            });
            
          case TTypedecl(t):
            process(t, TypeId.TYPEDEF); 
            
          case TAbstractdecl(a):
            process(a, TypeId.ABSTRACT);
        }
      }
    }
    
    inline function getPlatformName(file:String) return file.replace(".xml", "");
    
    // read xmls in directory. process xml docs using rtti.XmlParser
    var parser = new XmlParser();
    for (file in FileSystem.readDirectory(directory)) {
      if (file.indexOf(".xml") == -1) continue;
      var xml = Xml.parse(File.getContent(directory + file));
      var platform = getPlatformName(file);
      if (!stats.exists(platform)) stats.set(platform, new Stat(platform));
      parser.process(xml.firstElement(), platform);
    }
    
    // here starts the search for statistics
    collect(parser.root);
    
    // sum up all stats
    var log = "";
    var totals = new Stat("total");
    for (stat in stats) {
      log += stat.toString();
      totals.add(stat);
    }
    log += "-- total -- \n\n" + totals.toString();
    trace(log);
    //File.saveContent(logPath, directory + "log.txt");
    
    // load template, execute, save as file
    var template = Template.fromFile(templatePath);
    File.saveContent(outputPath, template.execute({
      stats: [for (stat in stats) stat],
      subStats: [for (stat in stats) stat.name => [for (s in subStats) if (s.name.startsWith(stat.name)) s]],
      totals: totals,
      title: directory.replace("/"," "),
    }));
  }
}

private class StatInfo {
  public var total:Int = 0;
  public var documented:Int = 0;
  
  public inline function new() { }
  
  public function getPercentage() {
    return toFixed(documented / total * 100.0, 2);
  }
  
  public function add(info:StatInfo) {
    total += info.total;
    documented += info.documented;
  }
  
  @:keep public function getProgressBar() {
    return HtmlTemplateUtils.getProgressBar(getPercentage());
  }
  
  static inline function toFixed(value:Float, precision) {
    return Math.floor(value * Math.pow(10, precision)) / Math.pow(10, precision);
  }
}

@:keep class Stat {
  public var name(default, null):String;
  
  public var types(default, null):StatInfo = new StatInfo();
  public var fields(default, null):StatInfo = new StatInfo();
  
  public var missingTypes(default, null):Array<String> = [];
  public var missingFields(default, null):Array<String> = [];
  
  private var _all:Array<StatInfo>;
  private var _collectMissing:Bool;
  
  public inline function new(name:String, collectMissing:Bool = false) {
    this.name = name;
    
    _collectMissing = collectMissing;
    _all = [types, fields];
  }
  
  /** Add stat into this **/
  public function add(stats:Stat) {
    for (i in 0 ... stats._all.length) {
      _all[i].add(stats._all[i]); // TODO: why can I access private fields here?
    }
  }
  
  /** Collect type info **/
  public function addTypeInfo(typeId:TypeId, type:TypeInfos, doc:String) {
    types.total++;
    if (hasDoc(doc)) {
      types.documented ++;
    } else if (_collectMissing) {
      missingTypes.push(type.path);
    }
  }
  
  /** Collect field info **/
  public function addFieldInfo(type:TypeInfos, field:{meta:MetaData, name:String}, doc:String) {
    fields.total++;
    if (hasDoc(doc)) {
      fields.documented ++;
    } else if (_collectMissing) {
      missingFields.push(type.path + "." + field.name);
    }
  }
  
  public function toString() {
    var newline = "\n";
    var v = '$name types: ${types.documented}/${types.total} = ${types.getPercentage()}% documented $newline';
    v += '$name members: ${fields.documented}/${fields.total} = ${fields.getPercentage()}% documented $newline$newline';
    return v;
  }
  
  public function getClassName(percentage:Float) {
    return HtmlTemplateUtils.getClassName(percentage);
  }
  
  inline function hasDoc(doc:String) return doc != null && doc.length > 1;
}

class HtmlTemplateUtils {
  public inline static function getClassName(percentage:Float) {
    return if (percentage < 10) "important";
           else if (percentage > 75) "success";
           else "warning";
  }
  
  static inline public function getProgressBar(percentage:Float) {
    return '<div class="progress"><div class="progress-bar progress-bar-${getClassName(percentage)}" style="width: ${percentage}%" aria-valuemin="0" aria-valuemax="100" role="progressbar" aria-valuenow="${Math.floor(percentage)}">${percentage}%</div></div>';
  }
}

@:enum abstract TypeId(Int) {
  public var CLASS = 1;
  public var ENUM = 2;
  public var TYPEDEF = 3;
  public var ABSTRACT = 4;
}
