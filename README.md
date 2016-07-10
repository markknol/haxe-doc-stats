# Haxe doc stats
> ### Are we documented yet?

Display how much your Haxe project is documented. 
This generator uses Neko to generate a static page with stats about your Haxe project code documentation. The tool is created to get more information about the Haxe Standard Library API documentation, but can be used for any project.

- Displays documentation amounts for types and its members (global and detailed per package)
- Packages can be expanded to see what is undocumented

## Preview

To see the stats of the Haxe Standard Library: <http://haxe.stroep.nl/api-stats/3.3/>

![api-stats](https://cloud.githubusercontent.com/assets/576184/16715856/554cec7e-46ec-11e6-804f-5ac23f174c40.gif)

## How to use
Add `-xml xml/` to your project build configuration (hxml or compilation flags). 
This will produce a .xml file in your project. 

Put it in a folder and run the following command:
```
neko DocStats.n xml/
```
This will produce a `index.html` file in the _xml/_ folder. 

---

For more specific use, there are more parameters:
```
neko DocStats.n arg0 arg1 arg2 arg3
  [arg0] path to xml directory. default: 'xml/'
  [arg1] path to output file. default: 'xml/index.html'
  [arg2] path to template html-file. default: 'layout.html' 
  [arg3] path to log-file. default: 'xml/log.txt
```

## Details

These are the rules/definitions used by this statistics:

 * "Types" can be classes, typedefs, abstracts, enums, interfaces.
 * "Members" are fields, functions, statics, enum constructors.
 * Everything that is private/override or has metadata `@:dox(hide)` or `@:noCompletion` gets skipped.
 * The quality of the documentation is not measured.
 * The colors work like this:
 
   * higher than 75% is good
   * lower than 10% is bad

## More

* The more documentation your project has, the better.
* Use [Dox](https://github.com/HaxeFoundation/dox) to generate API documentation for your project.
