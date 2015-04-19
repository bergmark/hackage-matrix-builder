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

    var cols = p.ghcVersions.length;
    var rows = p.versions.length;

    for (var y = 0; y < rows; y++) {
      var tr = $("<tr>").addClass("solver-row");
      var versionName = p.versions[y].version.name;
      for (var x = 0; x < cols; x++) {
        var td = $("<td>").addClass("stcell").addClass("lastmaj");
        var ghcVersion = p.ghcVersions[x];
        var ghcVersionName = ghcVersion.ghcVer.name;
        var res = ghcVersion.resultsA[y];
        td.attr("data-ghc-version", "ghc-" + ghcVersionName);
        td.attr("data-package-version", "version-" + versionName);y
        if (res.result.ok) {
          td.text("GHC-" + ghcVersionName + "/" + versionName + " OK");
          td.addClass("pass-build");
        } else if (res.result.fail) {
          td.text("GHC-" + ghcVersionName + "/" + versionName + " FAIL");
          td.addClass("fail-build");
        } else {
          console.warn("unhandled result: ", res.result);
        }
        tr.append(td);
      }
      t.append(tr);
    }

    var header = $("<tr>");
    t.find("tr").each(function (i, tr) {
      console.log(i,tr, p.versions[i].version.name);
      var th = $("<th>").addClass("pkgv").text(p.versions[i].version.name);
      $(tr).prepend(th);
    });

    t.prepend((function () {
      var tr = $("<tr>");
      tr.append($("<td>"));
      for (var i = 0; i < p.ghcVersions.length; i++) {
        tr.append($("<td>").text(p.ghcVersions[i].ghcVer.name));
      }
      return tr;
    })());

    $("#package").append(t);
  }

})();
