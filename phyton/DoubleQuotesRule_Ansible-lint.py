# Import necessary modules
import re  # Regular expression module for pattern matching
from ansiblelint.rules import AnsibleLintRule  # Base class for creating custom rules
from ansiblelint.errors import MatchError  # Class for reporting errors found by lint rules

# Define a new rule by extending AnsibleLintRule
class DoubleQuotedValuesRule(AnsibleLintRule):
    # Class attributes defining the rule's metadata
    id = 'DoubleQuotes'  # Unique identifier for the rule
    shortdesc = 'Check for values enclosed in double quotes'  # Short description of the rule
    description = 'This rule checks for the presence of values enclosed in double quotes'  # Detailed description
    tags = ['formatting']  # Tags categorizing the rule

    # The method that will be called to check each playbook
    def matchplay(self, file, play):
        print(f"Checking file: {file.path}")  # Log the file being checked

        try:
            with open(file.path, 'r') as f:  # Attempt to open the file for reading
                lines = f.readlines()  # Read all lines from the file
        except IOError:  # Handle error if file cannot be read
            print(f"Unable to read file: {file.path}")
            return []  # Return an empty list indicating no errors were found

        pattern = re.compile(r'"([^"]+)"')  # Compile a regex pattern to find double-quoted values

        errors = []  # Initialize a list to collect errors
        for i, line in enumerate(lines):  # Iterate over each line in the file
            for match in pattern.finditer(line):  # Search for the pattern in the current line
                # Construct an error message for each match
                match_message = f"{self.shortdesc}: '{match.group(1)}' found at line {i + 1}"
                print(match_message)  # Log the error message
                # Create a MatchError object for the error and add it to the list
                errors.append(MatchError(filename=str(file.path), message=match_message))

        if not errors:  # If no errors were found
            print(f"No values enclosed in double quotes found in {file.path}")  # Log a message indicating this

        return errors  # Return the list of errors found
