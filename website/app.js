(function ($) {
    $("#uploadForm").submit(function (event) {
        $("#uploadForm button").addClass('disabled');

        if (event.preventDefault)
            event.preventDefault();
        else
            event.returnValue = false;

        event.preventDefault();

        let fileName = $("#customFile").val().replace(/C:\\fakepath\\/i, '');
        let presignerUrl = $("#presignerUrl").val();

        // modify the original form
        console.log(fileName, presignerUrl);

        let urlToCall = presignerUrl + "/" + fileName
        console.log(urlToCall);

        let form = this;

        $.ajax({
            url: urlToCall,
            success: function (data) {
                console.log("got pre-signed POST URL", data);

                // set form fields to make it easier to serialize
                let fields = data['fields'];
                $(form).attr("action", data['url']);
                for (let key in fields) {
                    $("#" + key).val(fields[key]);
                }

                let formData = new FormData($("#uploadForm")[0]);
                console.log("sending form data", formData);

                $.ajax({
                    type: "POST",
                    url: data['url'],
                    data: formData,
                    processData: false,
                    contentType: false,
                    success: function () {
                        alert("success!");
                    },
                    error: function() {
                        alert("error! check the logs");
                    },
                    complete: function (event) {
                        console.log("done", event);
                        $("#uploadForm button").removeClass('disabled');
                    }
                });
            },
            error: function (e) {
                console.log("error", e);
                alert("error getting pre-signed URL. check the logs!");
                $("#uploadForm button").removeClass('disabled');
            }
        });
    });
})(jQuery);
