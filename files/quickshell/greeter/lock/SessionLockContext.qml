pragma ComponentBehavior: Bound
import Quickshell
import Quickshell.Services.Pam
import QtQuick

Scope {
	id: root
	signal unlocked();

	property var state: LockState {
		id: lockState
		onTryPasswordUnlock: {
			root.state.isUnlocking = true;
			pam.start();
		}
	}

	PamContext {
		id: pam
		configDirectory: "pam"
		config: "password.conf"

		onPamMessage: {
			if (pam.responseRequired) {
				pam.respond(root.state.currentText);
			} else if (pam.messageIsError) {
				root.state.currentText = "";
				root.state.failed = true;
				root.state.error = pam.message;
			} // else ignore
		}

		onCompleted: status => {
			const success = (status === PamResult.Success);

			if (!success) {
				root.state.currentText = "";
				root.state.error = "Invalid password";
			}

			root.state.failed = !success;
			root.state.isUnlocking = false;

			if (success) root.unlocked();
		}
	}
}
