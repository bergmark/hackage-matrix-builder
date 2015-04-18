(function () {
  var api = new MatrixApi( "http://localhost:3000/api"
                         , "http://localhost:3000/api"
                         );

  $(window).ready(main);

  function fail (msg) {
    return function () {
      console.warn("request failed", msg, arguments);
    };
  }

  function main () {
    api.Package.list(function ok (l) {

      var s = $("<select/>");
      s.change(function () {
        selectedPackage($(this).val());
      });
      l.items.forEach(function (v) {
        var li = $("<option/>").text(v).attr("value", v);
        s.append(li);
      });
      $("#package-list").append(s);

      if (l.items.length > 0) {
        console.log(l.items[0]);
        selectedPackage(l.items[0]);
      }

    }, fail("Package.list"));
  }

  function selectedPackage (pkgName) {
    api.Package.byName(pkgName).get(packageLoaded, fail("Package.byName"));
  }

  function packageLoaded (p) {
    $("#package").html("");
    var t = $("<table>");

    var ghcVersions = [];
    for (var gv in p.rdjGVersions) {
      ghcVersions.push({ key : gv, name : p.rdjGVersions[gv][0] });
    }
    var tr = $("<tr>");
    tr.append("<td>");
    tr.append(ghcVersions.map(function (gv) {
      return $("<td>").text(gv.name);
    }))
    t.append(tr);

    var vs = [];
    for (var v in p.rdjVersions) {
      vs.push(v);
    }
    vs.sort();

    vs.forEach(function (v) {
      var tr = $("<tr>");
      $("<td>").text(v).appendTo(tr);
      for (var gv in p.rdjGVersions) {

      }
      t.append(tr);
    });

    $("#package").append(t);
  }

})();
