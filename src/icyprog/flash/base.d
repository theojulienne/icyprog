module icyprog.flash.base;

import icyprog.board;
import icyprog.chip;
import icyprog.memory;

class Flash : Memory {
	this( Chip c ) {
		super( c );
	}
}
