/*
 * parser for _simplified_ MSC (messsage sequence chart)
 * Designed to make creating sequence charts as effortless as possible
 *
 * mscgen features supported:
 * - All arc types
 * - All options
 *
 * not supported (by design):
 * - all types of coloring, arcskip, id, url, idurl
 *
 * extra features:
 * - implicit entity declaration
 * - quoteless strings quotes
 * - low effort labels
 * - no need to enclose in msc { ... }
 * - inline expressions
 *
 * The resulting abstract syntax tree is compatible with the one
 * generated by the mscgenparser, so all renderers for mscgen can
 * be used for ms genny scripts as well.
 *
 */

{
    function mergeObject (pBase, pObjectToMerge){
        if (pObjectToMerge){
            Object.getOwnPropertyNames(pObjectToMerge).forEach(function(pAttribute){
                pBase[pAttribute] = pObjectToMerge[pAttribute];
            });
        }
    }
        
    function merge(pBase, pObjectToMerge){
        pBase = pBase ? pBase : {};
        mergeObject(pBase, pObjectToMerge);
        return pBase;
    }

    function optionArray2Object (pOptionList) {
        var lOptionList = {};
        pOptionList[0].forEach(function(lOption){
            lOptionList = merge(lOptionList, lOption);
        });
        return merge(lOptionList, pOptionList[1]);
    }

    function flattenBoolean(pBoolean) {
        return (["true", "on", "1"].indexOf(pBoolean.toLowerCase()) > -1).toString();
    }

    function entityExists (pEntities, pName, pEntityNamesToIgnore) {
        if (pName === undefined || pName === "*") {
            return true;
        }
        if (pEntities.entities.some(function(pEntity){
            return pEntity.name === pName;
        })){
            return true;
        }
        return pEntityNamesToIgnore[pName] === true;
    }

    function initEntity(lName ) {
        var lEntity = {};
        lEntity.name = lName;
        return lEntity;
    }

    function extractUndeclaredEntities (pEntities, pArcLineList, pEntityNamesToIgnore) {
        if (!pEntities) {
            pEntities = {};
            pEntities.entities = [];
        }

        if (!pEntityNamesToIgnore){
            pEntityNamesToIgnore = {};
        }

        if (pArcLineList && pArcLineList.arcs) {
            pArcLineList.arcs.forEach(function(pArcLine){
                pArcLine.forEach(function(pArc){
                    if (!entityExists (pEntities, pArc.from, pEntityNamesToIgnore)) {
                        pEntities.entities[pEntities.entities.length] =
                            initEntity(pArc.from);
                    }
                    // if the arc kind is arcspanning recurse into its arcs
                    if (pArc.arcs){
                        pEntityNamesToIgnore[pArc.to] = true;
                        merge (pEntities, extractUndeclaredEntities (pEntities, pArc, pEntityNamesToIgnore));
                        delete pEntityNamesToIgnore[pArc.to];
                    }
                    if (!entityExists (pEntities, pArc.to, pEntityNamesToIgnore)) {
                        pEntities.entities[pEntities.entities.length] =
                            initEntity(pArc.to);
                    }
                });
            });
        }
        return pEntities;
    }

    function hasExtendedOptions (pOptions){
        if (pOptions && pOptions.options){
            return pOptions.options["watermark"] ? true : false;
        } else {
            return false;
        }
    }

    function hasExtendedArcTypes(pArcLineList){
        if (pArcLineList && pArcLineList.arcs){
            return pArcLineList.arcs.some(function(pArcLine){
                return pArcLine.some(function(pArc){
                    return (["alt", "else", "opt", "break", "par",
                      "seq", "strict", "neg", "critical",
                      "ignore", "consider", "assert",
                      "loop", "ref", "exc"].indexOf(pArc.kind) > -1);
                });
            });
        }
        return false;
    }

    function getMetaInfo(pOptions, pArcLineList){
        var lHasExtendedOptions  = hasExtendedOptions(pOptions);
        var lHasExtendedArcTypes = hasExtendedArcTypes(pArcLineList);
        return {
            "extendedOptions" : lHasExtendedOptions,
            "extendedArcTypes": lHasExtendedArcTypes,
            "extendedFeatures": lHasExtendedOptions||lHasExtendedArcTypes
        }
    }
}

program         =  pre:_ d:declarationlist _
{
    d[1] = extractUndeclaredEntities(d[1], d[2]);
    var lRetval = merge (d[0], merge (d[1], d[2]));

    lRetval = merge ({meta: getMetaInfo(d[0], d[2])}, lRetval);
    
    if (pre.length > 0) {
        lRetval = merge({precomment: pre}, lRetval);
    }
/*
    if (post.length > 0) {
        lRetval = merge(lRetval, {postcomment:post});
    }
*/
    return lRetval;
}

declarationlist = (o:optionlist {return {options:o}})?
                  (e:entitylist {return {entities:e}})?
                  (a:arclist {return {arcs:a}})?
optionlist      = options:((o:option "," {return o})*
                  (o:option ";" {return o}))
{
  return optionArray2Object(options);
}

option          = _ name:optionname _ "=" _
                  value:(s:quotedstring {return s}
                     / i:number {return i.toString()}
                     / b:boolean {return b.toString()}) _
{
  var lOption = {};
  name = name.toLowerCase();
  if (name === "wordwraparcs"){
    lOption[name] = flattenBoolean(value);
  } else {
    lOption[name]=value;
  }
  return lOption;
}
optionname      = "hscale"i / "width"i / "arcgradient"i
                  /"wordwraparcs"i / "watermark"i
entitylist      = el:((e:entity "," {return e})* (e:entity ";" {return e}))
{
  el[0].push(el[1]);
  return el[0];
}
entity "entity" =  _ name:identifier _ label:(":" _ l:string _ {return l})?
{
  var lEntity = {};
  lEntity.name = name;
  if (!!label) {
    lEntity.label = label;
  }
  return lEntity;
}
arclist         = (a:arcline _ ";" {return a})+
arcline         = al:((a:arc "," {return a})* (a:arc {return [a]}))
{
   al[0].push(al[1][0]);

   return al[0];
}
arc             = regulararc/ spanarc
regulararc      = ra:((sa:singlearc {return sa})
                / (da:dualarc {return da})
                / (ca:commentarc {return ca}))
                  label:(":" _ s:string _ {return s})?
{
  if (label) {
    ra.label = label;
  }
  return ra;
}

singlearc       = _ kind:singlearctoken _ {return {kind:kind}}
commentarc      = _ kind:commenttoken _ {return {kind:kind}}
dualarc         =
 (_ from:identifier _ kind:dualarctoken _ to:identifier _
  {return {kind: kind, from:from, to:to}})
/(_ "*" _ kind:bckarrowtoken _ to:identifier _
  {return {kind:kind, from: "*", to:to}})
/(_ from:identifier _ kind:fwdarrowtoken _ "*" _
  {return {kind:kind, from: from, to: "*"}})
spanarc         =
 (_ from:identifier _ kind:spanarctoken _ to:identifier _ label:(":" _ s:string _ {return s})? "{" _ arcs:arclist? _ "}" _
  {
    var retval = {kind: kind, from:from, to:to, arcs:arcs};
    if (label) {
      retval.label = label;
    }
    return retval;
  })

singlearctoken  = "|||" / "..."
commenttoken    = "---"
dualarctoken    = kind:(
                    bidiarrowtoken/ fwdarrowtoken / bckarrowtoken
                  / boxtoken)
                 {return kind.toLowerCase()}
bidiarrowtoken   "bi-directional arrow"
                =   "--"  / "<->"
                  / "=="  / "<<=>>"
                          / "<=>"
                  / ".."  / "<<>>"
                  / "::"  / "<:>"
fwdarrowtoken   "left to right arrow"
                = "->" / "=>>"/ "=>" / ">>"/ ":>" / "-x"i
bckarrowtoken   "right to left arrow"
                = "<-" / "<<=" / "<=" / "<<" / "<:" / "x-"i
boxtoken        "box"
                = "note"i / "abox"i / "rbox"i / "box"i
spanarctoken    "arc spanning box"
                = kind:("alt"i / "else"i/ "opt"i / "break"i /"par"i
                  / "seq"i / "strict"i / "neg"i / "critical"i
                  / "ignore"i / "consider"i / "assert"i
                  / "loop"i / "ref"i / "exc"i
                  )
                 {return kind.toLowerCase()}
string          = quotedstring / unquotedstring
quotedstring    = '"' s:stringcontent '"' {return s.join("")}
stringcontent   = (!'"' c:('\\"'/ .) {return c})*
unquotedstring  = s:nonsep {return s.join("").trim()}
nonsep          = (!(',' /';' /'{') c:(.) {return c})*

/*
 * These unicode code pointranges come from
 * http://www.unicode.org/Public/UCD/latest/ucd/Scripts.txt
 *
 * var HAN_CHAR  = "\u2E80-\u2E99|\u2E9B-\u2EF3|\u2F00-\u2FD5|\u3005|\u3007|\u3021-\u3029|\u3038-\u303A|\u303B|\u3400-\u4DB5|\u4E00-\u9FCC|\uF900-\uFA6D|\uFA70-\uFAD9";
 * var YI_CHAR   = "\uA000-\uA014|\uA015|\uA016-\uA48C|\uA490-\uA4C6";
 * var HANGUL_CHAR = "\u1100-\u11FF|\u302E-\u302F|\u3131-\u318E|\u3200-\u321E|\u3260-\u327E|\uA960-\uA97C|\uAC00-\uD7A3|\uD7B0-\uD7C6|\uD7CB-\uD7FB|\uFFA0-\uFFBE|\uFFC2-\uFFC7|\uFFCA-\uFFCF|\uFFD2-\uFFD7|\uFFDA-\uFFDC";
 * var HIRAGANA_CHAR = "\u3041-\u3096|\u309D-\u309E|\u309F"; // also the astral points 1B001 and 1F200
 * var KATAKANA_CHAR = "\u30A1-\u30FA|\u30FD-\u30FE|\u30FF|\u31F0-\u31FF|\u32D0-\u32FE|\u3300-\u3357|\uFF66-\uFF6F|\uFF71-\uFF9D"; // also astral 1B000

1B000         ; Katakana # Lo       KATAKANA LETTER ARCHAIC E
// = (letters:([A-Za-z_0-9|\u2E80-\u2E99|\u2E9B-\u2EF3|\u2F00-\u2FD5|\u3005|\u3007|\u3021-\u3029|\u3038-\u303A|\u303B|\u3400-\u4DB5|\u4E00-\u9FCC|\uF900-\uFA6D|\uFA70-\uFAD9|\uA000-\uA014|\uA015|\uA016-\uA48C|\uA490-\uA4C6|\u1100-\u11FF|\u302E-\u302F|\u3131-\u318E|\u3200-\u321E|\u3260-\u327E|\uA960-\uA97C|\uAC00-\uD7A3|\uD7B0-\uD7C6|\uD7CB-\uD7FB|\uFFA0-\uFFBE|\uFFC2-\uFFC7|\uFFCA-\uFFCF|\uFFD2-\uFFD7|\uFFDA-\uFFDC|\u3041-\u3096|\u309D-\u309E|\u309F|\u30A1-\u30FA|\u30FD-\u30FE|\u30FF|\u31F0-\u31FF|\u32D0-\u32FE|\u3300-\u3357|\uFF66-\uFF6F|\uFF71-\uFF9D])+ {return letters.join("")})
 */

identifier "identifier"
   = (letters:([^;, \"\t\n\r=\-><:\{\*])+ {return letters.join("")})
  / quotedstring

whitespace "whitespace"
                = c:[ \t] {return c}
lineend "lineend"
                = c:[\r\n] {return c}
mlcomstart      = "/*"
mlcomend        = "*/"
mlcomtok        = !"*/" c:. {return c}
mlcomment       = start:mlcomstart com:(mlcomtok)* end:mlcomend
{
  return start + com.join("") + end
}
slcomstart      = "//" / "#"
slcomtok        = [^\r\n]
slcomment       = start:(slcomstart) com:(slcomtok)*
{
  return start + com.join("")
}
comment "comment"
                =   slcomment
                  / mlcomment
_               = (whitespace / lineend/ comment)*

number = real / integer
integer "integer"
  = digits:[0-9]+ { return parseInt(digits.join(""), 10); }

real "real"
  = digits:([0-9]+ "." [0-9]+) { return parseFloat(digits.join("")); }

boolean "boolean"
  = "true"i / "false"i/ "on"i/ "off"i

/*
 This file is part of mscgen_js.

 mscgen_js is free software: you can redistribute it and/or modify
 it under the terms of the GNU General Public License as published by
 the Free Software Foundation, either version 3 of the License, or
 (at your option) any later version.

 mscgen_js is distributed in the hope that it will be useful,
 but WITHOUT ANY WARRANTY; without even the implied warranty of
 MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
 GNU General Public License for more details.

 You should have received a copy of the GNU General Public License
 along with mscgen_js.  If not, see <http://www.gnu.org/licenses/>.
 */
