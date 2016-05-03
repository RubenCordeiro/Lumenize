Ext.data.JsonP.Lumenize_RandomPicker({"tagname":"class","name":"Lumenize.RandomPicker","autodetected":{},"files":[{"filename":"RandomPicker.coffee.js","href":"RandomPicker.coffee.html#Lumenize-RandomPicker"}],"members":[],"alternateClassNames":[],"aliases":{},"id":"class-Lumenize.RandomPicker","short_doc":"Takes a config object like the one shown below, with the same format as is output by Lumenize.histogram()\n\nconfig =\n ...","component":false,"superclasses":[],"subclasses":[],"mixedInto":[],"mixins":[],"parentMixins":[],"requires":[],"uses":[],"html":"<div><pre class=\"hierarchy\"><h4>Files</h4><div class='dependency'><a href='source/RandomPicker.coffee.html#Lumenize-RandomPicker' target='_blank'>RandomPicker.coffee.js</a></div></pre><div class='doc-contents'><p>Takes a config object like the one shown below, with the same format as is output by <a href=\"#!/api/Lumenize.histogram\" rel=\"Lumenize.histogram\" class=\"docClass\">Lumenize.histogram</a>()</p>\n\n<pre><code>config =\n  histogram: [\n    { label: '&lt; 10', count: 1 },  # histogram fields index, startOn, and endBelow are ignored, but returned by getRow() if provided\n    { label: '10-20', count: 10 },\n    { label: '20-30', count: 102 },\n    { label: '30-40', count: 45},\n    { label: '&gt;= 40', count: 7}\n  ]\n</code></pre>\n\n<p>So that it will make more sense when used with hand generated distributions, it will also take the following</p>\n\n<pre><code>config =\n  distribution: [\n    { value: -1.0, p: 0.25 }\n    { value:  2.0, p: 0.50 },\n    { value:  8.0, p: 0.25 }\n  ]\n</code></pre>\n\n<p>Note, that it runs the same exact code, just replacing what fields are used for the frequencyField and returnValueField\nSimilarly, you can override these by explicitly including them in your config.</p>\n\n<p>Also, note that you need not worry about making your 'p' values add up to 1.0. It figures out the portion of the total</p>\n</div><div class='members'></div></div>","meta":{}});