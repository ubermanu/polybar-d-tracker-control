import sys.io.Process;
import haxe.Exception;
import captain.Command;

var format:String = " <task-name> (<task-project>) <elapsed-time>";
var formatInactive:String = "%{F#6b6b6b} Start a new task%{F-}";
var notifications:Bool = true;

class Task {
    public var id:Null<Int> = null;
    public var description:String = "";
    public var project:String = "";
    public var startedAt:Null<Date> = null;
    public var endedAt:Null<Date> = null;

    public function new() {}

    public function isActive():Bool {
        return this.endedAt == null;
    }

    public function elapsedTime() {}

    // TODO: Implement this
    public function format(params:Array<Any>):String {
        return "";
    }
}

// remove the new line at the end of the cmd output
function exec(cmd:String) {
    var stdout = new Process(cmd).stdout.readAll().toString();
    return stdout.substr(0, stdout.length - 1);
}

function parseDate(str:String):Null<Date> {
    if (str == '---') {
        return null;
    }
    return Date.fromString(StringTools.replace(str, 'T', ' '));
}

function sendNotification(title:String, summary:String):Void {
    if (notifications) {
        Sys.command('notify-send "$title" "$summary"');
    }
}

final class DTracker {
    static public var tasks:Array<Task> = [];
    static public var projects:Array<String> = [];

    static public function assertInstalled() {
        if (exec('which d-tracker-cli').length == 0) {
            throw new Exception('Could not find d-tracker-cli in path');
        }
    }

    static public function fetchTodayTasks():Void {
        var stdout = exec('d-tracker-cli list-today-tasks | sed 1,2d');

        if (stdout.length == 0) {
            return;
        }

        for (line in stdout.split('\n')) {
            var data = line.split('|');
            var task = new Task();
            task.id = Std.parseInt(data[0]);
            task.description = data[4];
            task.project = data[1];
            task.startedAt = parseDate(data[2]);
            task.endedAt = parseDate(data[3]);
            DTracker.tasks.push(task);
        }
    }

    static public function createTask(task:Task):Void {
        if (task.description.length == 0) {
            throw new Exception('The task description cannot be empty');
        }
        if (task.project.length == 0) {
            throw new Exception('The task project cannot be empty');
        }
    }

    static public function getActiveTask():Null<Task> {
        var tasks = DTracker.tasks;
        tasks.reverse();
        for (task in tasks) {
            if (task.isActive()) {
                return task;
            }
        }
        return null;
    }

    // when splitting an empty string it returns an array with one empty value
    static public function getProjects():Array<String> {
        var stdout = exec("d-tracker-cli list-projects | sed 's/^[0-9]\\+|//g' | sort");
        return stdout.length > 0 ? stdout.split('\n') : [];
    }
}

final class DTrackerControl {
    static public var command = new Command(Sys.args());

    static public function main() {
        try {
            DTracker.assertInstalled();
        } catch (e:Exception) {
            Sys.println(e.message);
            Sys.exit(1);
        }

        DTracker.fetchTodayTasks();

        command.arguments = [
            {
                name: "action",
                description: "output, new, stop, toggle",
            },
        ];

        command.options = [
            {
                name: "help",
                shortName: "h",
                description: "Print this help message.",
                boolean: true,
            },
            {
                name: "format",
                shortName: "f",
                description: "Set the format for the output.",
            },
            {
                name: "format-inactive",
                shortName: "i",
                description: "Set the format for the inactive state.",
            },
            {
                name: "notifications",
                shortName: "n",
                description: "Enable or disable notifications.",
            },
        ];

        if (command.getOption("help") != None) {
            Sys.println(command.getInstructions());
            return;
        }

        switch (command.getArgument("action")) {
            case Some(value):
                {
                    switch (value) {
                        case "output": return DTrackerControl.commandOutput();
                        case "new": return DTrackerControl.commandNew();
                        case "stop": return DTrackerControl.commandStop();
                        case "toggle": return DTrackerControl.commandToggle();
                    }
                }
            case None:
                {}
        };

        Sys.println(command.getInstructions());
    }

    static public function commandOutput() {
        var task = DTracker.getActiveTask();
        if (task != null) {
            Sys.println(task.description);
        } else {
            Sys.println("No task started");
        }
    }

    // TODO: Add support for other input methods than rofi
    static public function commandNew() {
        var project = exec('echo "${DTracker.getProjects().join('\n')}" | rofi -dmenu -theme-str \'entry { placeholder: "What project are you working on?"; }\'');

        if (project.length == 0) {
            Sys.exit(1);
        }

        // TODO: Add project in the placeholder msg
        var description = exec('echo "" | rofi -dmenu -theme-str \'entry { placeholder: "What are you going to do?"; } listview { enabled: false; }\'');

        if (description.length == 0) {
            Sys.exit(1);
        }

        Sys.command('d-tracker-cli add-task', [description, project]);

        sendNotification("Task started", [
            'Description: ${description}',
            'Project: ${project}',
            'Started At: ${DateTools.format(Date.now(), "%T")}'
        ].join('\n'));
    }

    static public function commandStop() {
        var task = DTracker.getActiveTask();
        if (task != null) {
            Sys.command("d-tracker-cli stop-in-progress");
            sendNotification("Task stopped", [
                'Description: ${task.description}',
                'Project: ${task.project}',
                'Started At: ${DateTools.format(task.startedAt, "%T")}',
                'Stopped At: ${DateTools.format(Date.now(), "%T")}'
            ].join('\n'));
        }
    }

    static public function commandToggle() {
        var task = DTracker.getActiveTask();
        if (task != null) {
            DTrackerControl.commandStop();
        } else {
            DTrackerControl.commandNew();
        }
    }
}
